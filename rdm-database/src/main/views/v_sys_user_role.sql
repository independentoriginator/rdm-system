create or replace view v_sys_user_role
as
select
	u.rolname as user_name
	, r.rolname as role_name
from
	pg_catalog.pg_roles u
join pg_catalog.pg_auth_members m
	on m.member = u.oid
join pg_catalog.pg_roles r 
	on r.oid = m.roleid
where 
	u.rolcanlogin
	