#!/usr/bin/env python3
"""Publish an already signed release from a dedicated release payload branch.

No private signing keys are needed by GitHub Actions. --validate-only is local
and never contacts GitHub. Existing releases are never overwritten.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import urllib.parse
import xml.etree.ElementTree as ET
import zipfile

REPOSITORY = 'abdializ/Slate'

def validate(root):
    payload = root / '.release'
    manifest = json.loads((payload / 'manifest.json').read_text())
    version = manifest['version']
    build = manifest['build']
    source = manifest['source_sha']
    if not re.fullmatch(r'\d+\.\d+\.\d+', version) or not re.fullmatch(r'\d+(\.\d+)*', build):
        raise ValueError('Invalid release version')
    if not re.fullmatch(r'[a-f0-9]{40}', source):
        raise ValueError('Invalid source commit')
    archive = payload / f'Slate-{version}.zip'
    if hashlib.sha256(archive.read_bytes()).hexdigest() != manifest['sha256']:
        raise ValueError('Archive checksum mismatch')
    with zipfile.ZipFile(archive) as z:
        info = plistlib.loads(z.read('Slate.app/Contents/Info.plist'))
    if (info['CFBundleIdentifier'], info['CFBundleShortVersionString'], info['CFBundleVersion']) != ('dev.slate.browser', version, build):
        raise ValueError('Archive identity/version mismatch')
    if info.get('SlateVerificationEnabled', True):
        raise ValueError('Verification builds cannot be published')
    if not info.get('SURequireSignedFeed') or not info.get('SUVerifyUpdateBeforeExtraction'):
        raise ValueError('The updater must require signed feeds and archives')
    if info.get('SUPublicEDKey') != (root / 'updates/public-key.txt').read_text().strip():
        raise ValueError('Unexpected update public key')
    if info.get('SUFeedURL') != f'https://github.com/{REPOSITORY}/releases/latest/download/appcast.xml':
        raise ValueError('Unexpected update feed')
    feed = payload / 'appcast.xml'
    ns = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
    item = ET.parse(feed).find('./channel/item')
    enclosure = item.find('enclosure')
    if item.findtext(ns + 'version') != build or item.findtext(ns + 'shortVersionString') != version:
        raise ValueError('Feed version mismatch')
    if enclosure.get('url') != f'https://github.com/{REPOSITORY}/releases/download/v{version}/{archive.name}':
        raise ValueError('Unexpected archive destination')
    if int(enclosure.get('length')) != archive.stat().st_size or not enclosure.get(ns + 'edSignature'):
        raise ValueError('Feed enclosure mismatch')
    if b'<!-- sparkle-signatures:' not in feed.read_bytes() or b'edSignature:' not in feed.read_bytes():
        raise ValueError('The feed must already be signed')
    notes = payload / 'notes.md'
    if not notes.read_text().strip():
        raise ValueError('Release notes are required')
    return manifest, archive, feed, notes

def remove_published_branch(manifest, feed):
    """Remove only this job's unchanged staging branch, after verifying assets."""
    version = manifest['version']
    if not re.fullmatch(r'\d+\.\d+\.\d+', version):
        raise ValueError('Invalid cleanup version')
    branch = f'release/v{version}'
    expected = os.environ.get('GITHUB_SHA', '')
    if (os.environ.get('GITHUB_REPOSITORY') != REPOSITORY
            or os.environ.get('GITHUB_REF') != f'refs/heads/{branch}'
            or not re.fullmatch(r'[a-f0-9]{40}', expected)):
        raise ValueError('Cleanup is restricted to the current release job')

    def api(path):
        return json.loads(subprocess.check_output(['gh', 'api', f'repos/{REPOSITORY}/{path}'], text=True))

    release = api(f'releases/tags/v{version}')
    assets = {item['name']: item.get('digest') for item in release.get('assets', [])}
    if (release.get('draft', True) or release.get('prerelease', True)
            or release.get('target_commitish') != manifest['source_sha']
            or assets.get(f'Slate-{version}.zip') != 'sha256:' + manifest['sha256']
            or assets.get('appcast.xml') != 'sha256:' + hashlib.sha256(feed.read_bytes()).hexdigest()):
        raise ValueError('Published release must match the verified archive and signed feed before cleanup')
    head = urllib.parse.quote(REPOSITORY.split('/')[0] + ':' + branch, safe='')
    if api(f'pulls?state=open&head={head}'):
        raise ValueError('Release branch has an open pull request; preserving it')
    ref = api(f'git/ref/heads/{branch}')
    if ref.get('object', {}).get('sha') != expected:
        raise ValueError('Release branch moved after publication; preserving it')
    # Log the name and SHA before deletion for recovery. Never delete tags,
    # main, or a branch other than the exact staging branch for this job.
    print(f'Removing published staging branch {branch} at {expected}', flush=True)
    subprocess.run(['gh', 'api', '--method', 'DELETE', f'repos/{REPOSITORY}/git/refs/heads/{branch}'], check=True)

def publish(root, validate_only=False):
    manifest, archive, feed, notes = validate(root)
    version = manifest['version']
    if validate_only:
        print(f'Validated Slate {version}, build {manifest["build"]}; nothing published.')
        return
    if os.environ.get('GITHUB_REPOSITORY') != REPOSITORY or os.environ.get('GITHUB_REF') != f'refs/heads/release/v{version}':
        raise ValueError('Publication is restricted to this repository and release branch')
    parent = subprocess.check_output(['git', 'rev-parse', 'HEAD^'], cwd=root, text=True).strip()
    if parent != manifest['source_sha']:
        raise ValueError('The payload must be a direct child of its tested source commit')
    tag = f'v{version}'
    existing_tag = subprocess.run(['gh', 'api', f'repos/{REPOSITORY}/git/ref/tags/{tag}'],
                                  capture_output=True, text=True)
    if existing_tag.returncode == 0:
        if json.loads(existing_tag.stdout)['object']['sha'] != manifest['source_sha']:
            raise ValueError('An existing tag points to different source; refusing to replace it')
    elif '404' not in existing_tag.stderr:
        raise RuntimeError(existing_tag.stderr)
    # Creation fails if the release already exists. Upload into a draft so users
    # cannot receive a feed before its matching archive has finished uploading.
    subprocess.run(['gh', 'release', 'create', tag, '--repo', REPOSITORY,
                    '--target', manifest['source_sha'], '--title', f'Slate {version}',
                    '--notes-file', str(notes), '--draft'], check=True)
    subprocess.run(['gh', 'release', 'upload', tag, str(archive), str(feed),
                    '--repo', REPOSITORY], check=True)
    subprocess.run(['gh', 'release', 'edit', tag, '--repo', REPOSITORY,
                    '--draft=false', '--latest'], check=True)
    print(f'Published Slate {version}, build {manifest["build"]}.')
    remove_published_branch(manifest, feed)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--validate-only', action='store_true')
    args = parser.parse_args()
    publish(args.root.resolve(), args.validate_only)
