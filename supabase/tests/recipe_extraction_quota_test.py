"""Real PostgreSQL concurrency regression; requires initdb, pg_ctl and psql on PATH.

Starts an isolated temporary cluster with synthetic auth users; no production access.
Run: python3 supabase/tests/recipe_extraction_quota_test.py
"""
import concurrent.futures
import os
import getpass
from pathlib import Path
import subprocess
import tempfile
import unittest

MIGRATIONS = Path(__file__).resolve().parents[1] / "migrations"
USER_A = "00000000-0000-0000-0000-000000000001"
USER_B = "00000000-0000-0000-0000-000000000002"
USER_NEW = "00000000-0000-0000-0000-000000000003"
CUTOFF = "2026-10-12 00:00:00+00"


class QuotaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory(prefix="recipe-quota-")
        cls.addClassCleanup(cls.tmp.cleanup)
        cls.data = str(Path(cls.tmp.name) / "data")
        subprocess.run(["initdb", "-D", cls.data, "-A", "trust", "--no-locale"],
                       check=True, capture_output=True)
        subprocess.run(["pg_ctl", "-D", cls.data, "-l", f"{cls.tmp.name}/postgres.log",
                        "-o", f"-k {cls.tmp.name} -h ''", "-w", "start"],
                       check=True, capture_output=True)
        cls.addClassCleanup(lambda: subprocess.run(
            ["pg_ctl", "-D", cls.data, "-m", "immediate", "-w", "stop"],
            check=True, capture_output=True))
        cls.env = {**os.environ, "PGHOST": cls.tmp.name, "PGPORT": "5432",
                   "PGDATABASE": "postgres", "PGUSER": getpass.getuser()}
        cls.sql('''
            create extension "uuid-ossp";
            create schema auth;
            create table auth.users (
                id uuid primary key,
                created_at timestamptz not null default now()
            );
            create role anon;
            create role authenticated;
            create role service_role bypassrls;
            create role supabase_auth_admin;
            grant usage on schema public to anon, authenticated, service_role;
        ''')
        cls.sql((MIGRATIONS / "004_recipe_extraction_events.sql").read_text())
        # Supabase grants table access by default; RLS still excludes clients.
        cls.sql("grant all on public.recipe_extraction_events to anon, authenticated, service_role;")
        cls.sql((MIGRATIONS / "009_atomic_recipe_extraction_quota.sql").read_text())
        cls.sql(f"""
            insert into auth.users (id, created_at) values
              ('{USER_A}', timestamptz '{CUTOFF}' - interval '30 days'),
              ('{USER_B}', timestamptz '{CUTOFF}' - interval '1 day'),
              ('{USER_NEW}', timestamptz '{CUTOFF}' + interval '1 hour');
        """)
        cls.sql((MIGRATIONS / "011_billing_grandfathered_and_quota.sql").read_text())

    @classmethod
    def sql(cls, query, check=True):
        result = subprocess.run(["psql", "-X", "-qAt", "-v", "ON_ERROR_STOP=1", "-c", query],
                                env=cls.env, text=True, capture_output=True)
        if check and result.returncode:
            raise AssertionError(result.stderr)
        return result.stdout.strip() if check else result

    def setUp(self):
        self.sql("truncate public.recipe_extraction_events;")

    def reserve(self, user=USER_A):
        return self.sql(f"set role service_role; select public.reserve_recipe_extraction('{user}');")

    def seed(self, count, age="0 hours", user=USER_A):
        self.sql(f"""insert into public.recipe_extraction_events (user_id, created_at)
                     select '{user}', clock_timestamp() - interval '{age}'
                     from generate_series(1, {count});""")

    def burst(self, count, user=USER_A):
        with concurrent.futures.ThreadPoolExecutor(max_workers=count) as pool:
            return list(pool.map(lambda _: self.reserve(user), range(count)))

    def test_concurrent_empty_quota_admits_exactly_five(self):
        reservations = [slot for slot in self.burst(20) if slot]
        self.assertEqual(len(set(reservations)), 5)
        self.assertEqual(self.sql("select count(*) from recipe_extraction_events;"), "5")

    def test_concurrent_last_slot_admits_exactly_one(self):
        self.seed(4)
        self.assertEqual(sum(bool(slot) for slot in self.burst(12)), 1)
        self.assertEqual(self.sql("select count(*) from recipe_extraction_events;"), "5")

    def test_grandfathered_rolling_window_and_users_are_independent(self):
        self.seed(5, "25 hours")
        self.assertTrue(self.reserve())
        self.seed(4, "23 hours")
        self.assertEqual(self.reserve(), "")
        self.assertTrue(self.reserve(USER_B))

    def test_new_user_lifetime_quota_does_not_reset(self):
        self.seed(5, "25 hours", user=USER_NEW)
        self.assertEqual(self.reserve(USER_NEW), "")
        self.seed(4, "0 hours", user=USER_NEW)
        # Already at five lifetime; still blocked even with fresh day.
        self.assertEqual(self.reserve(USER_NEW), "")

    def test_new_user_admits_exactly_five_lifetime(self):
        reservations = [slot for slot in self.burst(12, user=USER_NEW) if slot]
        self.assertEqual(len(set(reservations)), 5)
        self.assertEqual(
            self.sql(f"select count(*) from recipe_extraction_events where user_id = '{USER_NEW}';"),
            "5",
        )

    def test_backfill_marks_pre_cutoff_accounts_grandfathered(self):
        self.assertEqual(
            self.sql(f"select grandfathered::text from user_accounts where id = '{USER_A}';"),
            "t",
        )
        self.assertEqual(
            self.sql(f"select grandfathered::text from user_accounts where id = '{USER_NEW}';"),
            "f",
        )

    def test_rollback_does_not_consume_slot(self):
        self.seed(4)
        self.sql(f"begin; set role service_role; select public.reserve_recipe_extraction('{USER_A}'); rollback;")
        self.assertTrue(self.reserve())
        self.assertEqual(self.reserve(), "")

    def test_rpc_and_table_reject_client_roles(self):
        for role in ("anon", "authenticated"):
            result = self.sql(f"set role {role}; select public.reserve_recipe_extraction('{USER_A}');", check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("permission denied for function", result.stderr)
            result = self.sql(f"set role {role}; insert into recipe_extraction_events (user_id) values ('{USER_A}');", check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("row-level security", result.stderr)


if __name__ == "__main__":
    unittest.main()
