-- Belt and braces: trigger firing does not check EXECUTE, but keep the auth
-- service's grant explicit so signup can never regress on the 005 revoke.
grant execute on function public.handle_new_user() to supabase_auth_admin;
