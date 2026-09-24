"""Exercise deployment ordering/failures with real Git and fake Docker/HTTPS."""
import gzip
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
LINUX_TOOLS = sys.platform.startswith('linux') and all(
    shutil.which(tool) for tool in ('bash', 'git', 'flock', 'tar', 'curl', 'python3'))


@unittest.skipUnless(LINUX_TOOLS, 'Updater targets Ubuntu; requires Linux shell tools')
class OracleUpdateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.app = self.root / 'app'
        self.source = self.root / 'source'
        self.repo = self.root / 'checkout'
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.source.mkdir()
        self.git(self.source, 'init', '-b', 'main')
        self.git(self.source, 'config', 'user.email', 'test@example.invalid')
        self.git(self.source, 'config', 'user.name', 'Deployment Test')
        (self.source / 'scripts').mkdir()
        shutil.copyfile(ROOT / 'scripts/backup_db.sh', self.source / 'scripts/backup_db.sh')
        (self.source / 'docker-compose.prod.yml').write_text('name: predicta\n')
        (self.source / 'version.txt').write_text('old')
        self.git(self.source, 'add', '.')
        self.git(self.source, 'commit', '-m', 'old release')
        self.old = self.git(self.source, 'rev-parse', 'HEAD')
        self.previous = self.app / 'releases' / self.old
        shutil.copytree(self.source, self.previous, ignore=shutil.ignore_patterns('.git'))
        self.private = 'DOMAIN=app.example.test\nDB_PASSWORD=private-test-value\n'
        (self.previous / '.env.production').write_text(self.private)
        (self.app / 'current').symlink_to(self.previous)
        self.git(self.root, 'clone', str(self.source), str(self.repo))
        (self.source / 'version.txt').write_text('new')
        self.git(self.source, 'commit', '-am', 'new main')
        self.new = self.git(self.source, 'rev-parse', 'HEAD')
        self.events = self.root / 'events.jsonl'
        fake = '''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
tool = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['EVENTS'], 'a') as log:
    log.write(json.dumps([tool, args]) + '\\n')
mode = os.environ.get('FAIL_PHASE')
if tool == 'curl':
    if mode == 'health': sys.exit(22)
    print(json.dumps({'status': 'ok', 'database': 'ok'}))
elif 'build' in args and mode == 'build': sys.exit(3)
elif 'up' in args and mode == 'start': sys.exit(4)
elif 'exec' in args:
    if mode == 'backup': sys.exit(5)
    print('CREATE TABLE example (id INT);')
elif 'config' in args and 'json' in args:
    print(json.dumps({'services': {'caddy': {'environment': {'DOMAIN': 'app.example.test'}}}}))
'''
        for tool in ('docker', 'curl'):
            path = self.bin / tool
            path.write_text(fake)
            path.chmod(0o755)
        self.env = dict(os.environ, PATH=f'{self.bin}:{os.environ["PATH"]}',
                        PREDICTA_ROOT=str(self.app), PREDICTA_REPO=str(self.repo),
                        EVENTS=str(self.events), FAIL_PHASE='')

    def git(self, folder, *args):
        return subprocess.check_output(['git', '-C', str(folder), *args],
                                       stderr=subprocess.DEVNULL, text=True).strip()

    def run_update(self, *args, fail=''):
        result = subprocess.run(['bash', str(ROOT / 'scripts/update_oracle.sh'), *args],
                                env=dict(self.env, FAIL_PHASE=fail),
                                text=True, capture_output=True, timeout=30)
        self.assertNotIn('private-test-value', result.stdout + result.stderr)
        return result

    def commands(self):
        return [json.loads(line) for line in self.events.read_text().splitlines()] if self.events.exists() else []

    def test_check_fetches_main_without_touching_runtime(self):
        result = self.run_update('--check')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(self.new, result.stdout)
        self.assertEqual((self.app / 'current').resolve(), self.previous)
        self.assertFalse((self.app / 'releases' / self.new).exists())
        self.assertEqual(self.commands(), [])
        self.assertEqual(self.git(self.repo, 'rev-parse', 'HEAD'), self.old)

    def test_success_preserves_secrets_and_backs_up_before_recreation(self):
        result = self.run_update()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        active = (self.app / 'current').resolve()
        self.assertEqual(active.name, self.new)
        self.assertEqual((active / 'version.txt').read_text(), 'new')
        private = active / '.env.production'
        self.assertEqual(private.read_text(), self.private)
        self.assertEqual(private.stat().st_mode & 0o777, 0o600)
        self.assertEqual((self.app / 'previous').resolve(), self.previous)
        backups = list((self.app / 'backups').glob('*.sql.gz'))
        self.assertEqual(len(backups), 1)
        self.assertIn('CREATE TABLE', gzip.decompress(backups[0].read_bytes()).decode())
        operations = [next((op for op in ('build', 'exec', 'up') if op in args), tool)
                      for tool, args in self.commands()]
        self.assertLess(operations.index('build'), operations.index('exec'))
        self.assertLess(operations.index('exec'), operations.index('up'))
        self.assertLess(operations.index('up'), operations.index('curl'))
        self.events.unlink()
        again = self.run_update()
        self.assertEqual(again.returncode, 0, again.stdout + again.stderr)
        self.assertFalse(any('up' in args or 'build' in args for _, args in self.commands()))

    def test_build_and_backup_failures_never_recreate_containers(self):
        for phase in ('build', 'backup'):
            with self.subTest(phase=phase):
                self.events.unlink(missing_ok=True)
                result = self.run_update(fail=phase)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual((self.app / 'current').resolve(), self.previous)
                self.assertFalse(any('up' in args for _, args in self.commands()))
                self.assertIn(f'FAILED during {phase}', result.stdout)

    def test_start_and_health_failures_keep_current_and_allow_retry(self):
        for phase in ('start', 'health'):
            with self.subTest(phase=phase):
                result = self.run_update(fail=phase)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual((self.app / 'current').resolve(), self.previous)
                self.assertIn('schema may already have changed', result.stdout)
        retry = self.run_update()
        self.assertEqual(retry.returncode, 0, retry.stdout + retry.stderr)
        self.assertEqual((self.app / 'current').resolve().name, self.new)

    def test_concurrent_update_is_rejected(self):
        import fcntl
        with (self.app / 'update.lock').open('w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = self.run_update()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Another update is running', result.stderr)
        self.assertEqual(self.commands(), [])
