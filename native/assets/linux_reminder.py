"""Deliver one validated reminder from The List's local database."""

import argparse
from contextlib import closing
import datetime as dt
import json
from pathlib import Path
import sqlite3
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--database', required=True)
    parser.add_argument('--id', required=True)
    parser.add_argument('--executable', required=True)
    args = parser.parse_args()

    database_uri = Path(args.database).resolve().as_uri() + '?mode=ro'
    with closing(sqlite3.connect(database_uri, uri=True)) as db:
        # Timers can outlive failed cancellation. Honor the current preference.
        enabled = db.execute(
            'SELECT value FROM settings WHERE key=?', ('notifications',)
        ).fetchone()
        if not enabled or enabled[0] != 'on':
            return
        row = db.execute(
            "SELECT project, fields FROM entities WHERE id=? AND kind='reminder'",
            (args.id,),
        ).fetchone()
        if not row:
            return
        project, raw = row
        reminder = json.loads(raw)
        if reminder.get('deleted') or reminder.get('done'):
            return
        target = db.execute(
            'SELECT project, fields FROM entities WHERE id=?',
            (reminder.get('target'),),
        ).fetchone()
        parent = db.execute(
            'SELECT fields FROM entities WHERE id=?', (project,)
        ).fetchone()
        if not target or not parent or target[0] != project:
            return
        if json.loads(target[1]).get('deleted') or json.loads(parent[0]).get('deleted'):
            return
        due = dt.datetime.fromisoformat(reminder['due'].replace('Z', '+00:00'))
        if due.tzinfo is None:
            due = due.astimezone()
        if due > dt.datetime.now(dt.timezone.utc) + dt.timedelta(seconds=5):
            return
        project_title = json.loads(parent[0]).get('title', 'The List')

    # Release the database before waiting for a desktop notification action.
    result = subprocess.run(
        [
            'notify-send',
            '--app-name=The List',
            '--action=open=Open',
            '--wait',
            '--',
            reminder.get('title', 'Reminder'),
            project_title,
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError('The desktop notification service could not deliver the reminder')
    if result.stdout.strip() == 'open':
        subprocess.Popen(
            [args.executable, '--open-target', reminder['target']],
            start_new_session=True,
        )


if __name__ == '__main__':
    main()
