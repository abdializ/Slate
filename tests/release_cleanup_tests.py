#!/usr/bin/env python3
"""Exercise deletion guards without credentials, network or a real repository."""
import hashlib, importlib.util, json, os, tempfile, unittest
from pathlib import Path
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('publisher', Path(__file__).resolve().parents[1]/'scripts/publish-prepared-release.py')
publisher=importlib.util.module_from_spec(spec);spec.loader.exec_module(publisher)

class ReleaseCleanupTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
  self.feed=Path(self.temp.name)/'appcast.xml';self.feed.write_bytes(b'signed feed')
  self.sha='a'*40
  self.manifest=dict(version='0.4.0',source_sha='b'*40,sha256='c'*64)
  self.release=dict(draft=False,prerelease=False,target_commitish='b'*40,assets=[dict(name='Slate-0.4.0.zip',digest='sha256:'+'c'*64),dict(name='appcast.xml',digest='sha256:'+hashlib.sha256(self.feed.read_bytes()).hexdigest())])
  self.pulls=[];self.ref={'object':{'sha':self.sha}}
  self.env=patch.dict(os.environ,{'GITHUB_REPOSITORY':'abdializ/Slate','GITHUB_REF':'refs/heads/release/v0.4.0','GITHUB_SHA':self.sha})
  self.env.start();self.addCleanup(self.env.stop)
  def answer(args,**kwargs):
   path=args[-1]
   if '/releases/tags/' in path:return json.dumps(self.release)
   if '/pulls?' in path:return json.dumps(self.pulls)
   if '/git/ref/heads/' in path:return json.dumps(self.ref)
   raise AssertionError(path)
  self.get=patch.object(publisher.subprocess,'check_output',side_effect=answer).start()
  self.delete=patch.object(publisher.subprocess,'run').start()
  self.addCleanup(patch.stopall)
 def reject(self):
  with self.assertRaises(ValueError):publisher.remove_published_branch(self.manifest,self.feed)
  self.delete.assert_not_called()
 def test_success_deletes_only_exact_release_head(self):
  publisher.remove_published_branch(self.manifest,self.feed)
  self.delete.assert_called_once_with(['gh','api','--method','DELETE','repos/abdializ/Slate/git/refs/heads/release/v0.4.0'],check=True)
 def test_never_delete_main(self):
  os.environ['GITHUB_REF']='refs/heads/main';self.reject();self.get.assert_not_called()
 def test_never_delete_other_repository(self):
  os.environ['GITHUB_REPOSITORY']='someone/else';self.reject();self.get.assert_not_called()
 def test_preserve_new_commits(self):
  self.ref['object']['sha']='d'*40;self.reject()
 def test_preserve_open_pull_request(self):
  self.pulls=[{'number':6}];self.reject()
 def test_preserve_unpublished_release(self):
  self.release['draft']=True;self.reject()
 def test_preserve_if_archive_mismatched(self):
  self.release['assets'][0]['digest']='sha256:'+'d'*64;self.reject()
 def test_preserve_if_feed_mismatched(self):
  self.feed.write_bytes(b'modified feed');self.reject()
 def test_preserve_if_release_targets_other_source(self):
  self.release['target_commitish']='e'*40;self.reject()
 def test_reject_untrusted_branch_name(self):
  self.manifest['version']='../../main';self.reject();self.get.assert_not_called()

if __name__=='__main__':unittest.main()
