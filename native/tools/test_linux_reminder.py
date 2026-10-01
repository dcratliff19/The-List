"""Exercise the Linux helper's database gates without a Linux desktop."""

from contextlib import closing
import importlib.util
import json
from pathlib import Path
import sqlite3
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    'reminder', Path(__file__).parents[1] / 'assets/linux_reminder.py'
)
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class ReminderTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.db = Path(self.temp.name) / 'the-list.sqlite'
        self.rows = [
            ('project', 'project', 'project', {'title': 'Project'}),
            ('note', 'project', 'note', {'title': 'Note'}),
            (
                'reminder', 'project', 'reminder',
                {
                    'title': 'Remember',
                    'target': 'note',
                    'due': '2020-01-01T00:00:00Z',
                },
            ),
        ]
        with closing(sqlite3.connect(self.db, isolation_level=None)) as conn:
            conn.execute('CREATE TABLE entities(id TEXT, project TEXT, kind TEXT, fields TEXT)')
            conn.execute('CREATE TABLE settings(key TEXT, value TEXT)')
            conn.execute("INSERT INTO settings VALUES('notifications', 'on')")
            for row in self.rows:
                conn.execute(
                    'INSERT INTO entities VALUES(?,?,?,?)',
                    (*row[:3], json.dumps(row[3])),
                )

    def tearDown(self):
        self.temp.cleanup()

    def run_helper(self, response=''):
        arguments = [
            'helper', '--database', str(self.db),
            '--id', 'reminder', '--executable', '/app/the_list',
        ]
        with (
            patch('sys.argv', arguments),
            patch.object(
                helper.subprocess, 'run',
                return_value=SimpleNamespace(returncode=0, stdout=response),
            ) as notify,
            patch.object(helper.subprocess, 'Popen') as opened,
        ):
            helper.main()
            return notify, opened

    def test_delivers_and_opens_correct_target(self):
        notify, opened = self.run_helper('open\n')
        self.assertEqual(notify.call_args.args[0][-2:], ['Remember', 'Project'])
        opened.assert_called_once_with(
            ['/app/the_list', '--open-target', 'note'], start_new_session=True
        )

    def test_completed_deleted_or_future_are_not_delivered(self):
        for fields in [
            {'done': True}, {'deleted': True}, {'due': '2099-01-01T00:00:00Z'},
        ]:
            with self.subTest(fields=fields):
                with closing(sqlite3.connect(self.db, isolation_level=None)) as conn:
                    value = {**self.rows[2][3], **fields}
                    conn.execute(
                        "UPDATE entities SET fields=? WHERE id='reminder'",
                        (json.dumps(value),),
                    )
                notify, opened = self.run_helper()
                notify.assert_not_called()
                opened.assert_not_called()

    def test_deleted_target_is_not_delivered(self):
        with closing(sqlite3.connect(self.db, isolation_level=None)) as conn:
            conn.execute(
                "UPDATE entities SET fields=? WHERE id='note'",
                (json.dumps({'deleted': True}),),
            )
        notify, _ = self.run_helper()
        notify.assert_not_called()

    def test_disabled_notifications_are_not_delivered(self):
        with closing(sqlite3.connect(self.db, isolation_level=None)) as conn:
            conn.execute("UPDATE settings SET value='off' WHERE key='notifications'")
        notify, opened = self.run_helper()
        notify.assert_not_called()
        opened.assert_not_called()

    def test_target_in_another_project_is_not_delivered(self):
        with closing(sqlite3.connect(self.db, isolation_level=None)) as conn:
            conn.execute("UPDATE entities SET project='other' WHERE id='note'")
        notify, _ = self.run_helper()
        notify.assert_not_called()


if __name__ == '__main__':
    unittest.main()
