#!/usr/bin/env python3
"""Prepare a signed in-app update. This command never publishes or exports private keys."""
import argparse
import datetime
import email.utils
import html
from pathlib import Path
import plistlib
import subprocess
import tempfile
import urllib.parse
import xml.etree.ElementTree as ET

REPO='abdializ/Slate'
ACCOUNT='dev.slate.browser'

def prepare(app, output, sparkle, notes):
    app=app.resolve(); output=output.resolve(); sparkle=sparkle.resolve()
    info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIdentifier')!='dev.slate.browser':
        raise ValueError('Expected the Slate application bundle')
    if info.get('SlateVerificationEnabled',True):
        raise ValueError('Only production builds may be published; turn SLATE_ENABLE_VERIFY off')
    if not info.get('SURequireSignedFeed') or not info.get('SUVerifyUpdateBeforeExtraction'):
        raise ValueError('Release must require signed feeds and verify updates before extraction')
    public=(Path(__file__).resolve().parents[1]/'updates/public-key.txt').read_text().strip()
    if info.get('SUPublicEDKey')!=public:
        raise ValueError('The app and release public keys do not match')
    version=info['CFBundleShortVersionString']; build=info['CFBundleVersion']
    if not all(piece.isdecimal() for piece in version.split('.')) or not all(piece.isdecimal() for piece in build.split('.')):
        raise ValueError('Release and build versions must contain increasing numeric components')
    expected_feed=f'https://github.com/{REPO}/releases/latest/download/appcast.xml'
    if info.get('SUFeedURL')!=expected_feed:
        raise ValueError('The build must point to this repository’s production update feed')
    output.mkdir(parents=True,exist_ok=True)
    archive=output/f'Slate-{version}.zip'
    if archive.exists() or (output/'appcast.xml').exists():
        raise ValueError('Use an empty output directory so an existing release cannot be overwritten')
    with tempfile.TemporaryDirectory(prefix='slate-release-',dir='/private/tmp') as temporary:
        staged=Path(temporary)/'Slate.app'
        subprocess.run(['/usr/bin/ditto','--norsrc','--noextattr',str(app),str(staged)],check=True)
        subprocess.run(['/usr/bin/codesign','--verify','--deep','--strict',str(staged)],check=True)
        subprocess.run(['/usr/bin/ditto','--norsrc','--noextattr','-c','-k','--keepParent',str(staged),str(archive)],check=True)
    release_notes=output/f'Slate-{version}.md'
    release_notes.write_text(notes.read_text() if notes else f'Slate {version}\n\nImprovements and fixes for Slate.\n')
    prefix=f'https://github.com/{REPO}/releases/download/v{version}/'
    # This release has one full archive and no channels or delta updates. Sign a
    # minimal standard appcast with Sparkle's own signer (the same format exercised
    # by the native updater regression), without the generator's global caches.
    ns='http://www.andymatuschak.org/xml-namespaces/sparkle'
    ET.register_namespace('sparkle',ns)
    signature=subprocess.check_output([str(sparkle/'bin/sign_update'),'--account',ACCOUNT,'-p',str(archive)],text=True,timeout=30).strip()
    rss=ET.Element('rss',version='2.0'); channel=ET.SubElement(rss,'channel')
    ET.SubElement(channel,'title').text='Slate Updates'
    ET.SubElement(channel,'link').text=f'https://github.com/{REPO}'
    ET.SubElement(channel,'description').text='Signed updates for Slate on macOS'
    item=ET.SubElement(channel,'item')
    ET.SubElement(item,'title').text=f'Slate {version}'
    ET.SubElement(item,'pubDate').text=email.utils.format_datetime(datetime.datetime.now(datetime.timezone.utc))
    ET.SubElement(item,f'{{{ns}}}version').text=build
    ET.SubElement(item,f'{{{ns}}}shortVersionString').text=version
    ET.SubElement(item,f'{{{ns}}}minimumSystemVersion').text=info.get('LSMinimumSystemVersion','12.0')
    ET.SubElement(item,'description').text='<pre>'+html.escape(release_notes.read_text())+'</pre>'
    ET.SubElement(item,'enclosure',{'url':prefix+urllib.parse.quote(archive.name),
        'length':str(archive.stat().st_size),'type':'application/octet-stream','os':'macos',f'{{{ns}}}edSignature':signature})
    ET.ElementTree(rss).write(output/'appcast.xml',encoding='utf-8',xml_declaration=True)
    subprocess.run([str(sparkle/'bin/sign_update'),'--account',ACCOUNT,str(output/'appcast.xml')],check=True,timeout=30)
    enclosure=ET.parse(output/'appcast.xml').find('./channel/item/enclosure')
    if enclosure is None or int(enclosure.attrib['length'])!=archive.stat().st_size:
        raise ValueError('Release feed does not match its archive')
    if enclosure.attrib['url']!=prefix+urllib.parse.quote(archive.name):
        raise ValueError('Release archive URL is unexpected')
    signature=enclosure.attrib['{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature']
    subprocess.run([str(sparkle/'bin/sign_update'),'--account',ACCOUNT,'--verify',str(archive),signature],check=True,timeout=30)
    subprocess.run([str(sparkle/'bin/sign_update'),'--account',ACCOUNT,'--verify',str(output/'appcast.xml')],check=True,timeout=30)
    print(f'Ready to publish tag v{version}, build {build}: {archive.name}, appcast.xml')
    return archive

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--sparkle',type=Path,default=Path(__file__).resolve().parents[1]/'third_party/Sparkle-2.10.1')
    parser.add_argument('--notes',type=Path)
    args=parser.parse_args()
    prepare(args.app,args.output,args.sparkle,args.notes)
