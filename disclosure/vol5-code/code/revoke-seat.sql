-- revoke-seat.sql - database steps of add-caged-seat.patched.sh revoke. Apache-2.0.
-- Usage (as a superuser):  psql -d membrane -v seat=<seat> -f revoke-seat.sql
-- Idempotent: safe to run twice (the shell script runs it before and after
-- killing the seat's processes, to catch a late reconnect).

-- 1) no new direct sessions for this role, by any authentication method
ALTER ROLE :"seat" NOLOGIN;

-- 2) deny list + edge path: list the seat in revoked_seats (current_holon() then
--    resolves to nothing for it on every path, including an edge session that already
--    switched to the role), and if an edge pooler ("authenticator") can assume the
--    role, take that away; the edge's pre-request check refuses tokens for it too.
SELECT EXISTS (SELECT 1 FROM pg_auth_members m
                 JOIN pg_roles r ON r.oid = m.roleid    AND r.rolname = :'seat'
                 JOIN pg_roles a ON a.oid = m.member    AND a.rolname = 'authenticator') AS edge_member,
       to_regclass('public.revoked_seats') IS NOT NULL AS has_deny_list
\gset
\if :edge_member
REVOKE :"seat" FROM authenticator;
\endif
\if :has_deny_list
INSERT INTO revoked_seats (rolename) VALUES (:'seat') ON CONFLICT (rolename) DO NOTHING;
\endif

-- 3) end every session already open as this role, and every edge (authenticator)
--    session: an edge session that already ran SET ROLE <seat> shows usename =
--    authenticator, so matching on the seat name alone would miss it. Edge sessions
--    reconnect on their own; the edge must use transaction-scoped SET LOCAL ROLE
--    (PostgREST does) so no session holds a seat role between requests.
--    (The deny-list row above already makes such a session resolve to no holon.)
SELECT pid, pg_terminate_backend(pid) AS terminated
  FROM pg_stat_activity
 WHERE (usename = :'seat' OR usename = 'authenticator') AND pid <> pg_backend_pid();
