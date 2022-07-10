create or replace view v_sys_obj_dependency
as
select distinct
	dependent_cls.oid as dependent_obj_id
	, dependent_cls.relname as dependent_obj_name
	, dependent_cls_ns.nspname as dependent_obj_schema
	, 'relation'::name as dependent_obj_class
	, dependent_cls.relkind as dependent_obj_type
	, master_cls.oid as master_obj_id
	, master_cls.relname as master_obj_name
	, master_cls_ns.nspname as master_obj_schema
	, 'relation'::name as master_obj_class
	, master_cls.relkind as master_obj_type
from
	pg_catalog.pg_class dependent_cls
join pg_catalog.pg_namespace dependent_cls_ns
	on dependent_cls_ns.oid = dependent_cls.relnamespace
join pg_catalog.pg_rewrite pg_rewrite
	on pg_rewrite.ev_class = dependent_cls.oid
join pg_catalog.pg_depend pg_depend
	on pg_depend.objid = pg_rewrite.oid
	and pg_depend.deptype = 'n' 
	and pg_depend.classid = 'pg_rewrite'::regclass
join pg_catalog.pg_class master_cls 
	on master_cls.oid = pg_depend.refobjid
	and master_cls.oid <> dependent_cls.oid					
join pg_catalog.pg_namespace master_cls_ns
	on master_cls_ns.oid = master_cls.relnamespace
union all
select distinct
	dependent_cls.oid as dependent_obj_id
	, dependent_cls.relname as dependent_obj_name
	, dependent_cls_ns.nspname as dependent_obj_schema
	, 'relation'::name as dependent_obj_class
	, dependent_cls.relkind as dependent_obj_type
	, master_proc.oid as master_obj_id
	, master_proc.proname as master_obj_name
	, master_proc_ns.nspname as master_obj_schema
	, 'routine'::name as master_obj_class
	, master_proc.prokind as master_obj_type
from
	pg_catalog.pg_class dependent_cls
join pg_catalog.pg_namespace dependent_cls_ns
	on dependent_cls_ns.oid = dependent_cls.relnamespace
join pg_catalog.pg_rewrite pg_rewrite
	on pg_rewrite.ev_class = dependent_cls.oid
join pg_catalog.pg_depend pg_depend
	on pg_depend.objid = pg_rewrite.oid
	and pg_depend.deptype = 'n' 
	and pg_depend.classid = 'pg_rewrite'::regclass
join pg_catalog.pg_proc master_proc 
	on master_proc.oid = pg_depend.refobjid
join pg_catalog.pg_namespace master_proc_ns
	on master_proc_ns.oid = master_proc.pronamespace
union all
select distinct
	p.oid as dependent_obj_id
	, p.proname as dependent_obj_name
	, n.nspname as dependent_obj_schema
	, 'routine'::name as dependent_obj_class
	, p.prokind as dependent_obj_type
	, sys_obj.obj_id as master_obj_id
	, sys_obj.obj_name as master_obj_name
	, sys_obj.obj_schema as master_obj_schema
	, sys_obj.obj_class as master_obj_class
	, sys_obj.obj_type as master_obj_type
from 
	pg_catalog.pg_proc p
join pg_catalog.pg_namespace n
	on n.oid = p.pronamespace
join lateral 
	unnest(
		string_to_array(
			regexp_replace(
				regexp_replace(
					lower(p.prosrc)
					, '--.*?\n'
					, '', 'g'
				)
				, '[^[:alnum:]_\.]+'
				, ' '
				, 'g'
			)
			, ' '
		)
	) as obj_candidate(obj_name)
	on true
join (
	select 
		n.nspname || '.' || c.relname as obj_full_name
		, c.oid as obj_id
		, c.relname as obj_name
		, n.nspname as obj_schema
		, c.relkind as obj_type
		, 'relation'::name as obj_class
	from 
		pg_catalog.pg_class c
	join pg_catalog.pg_namespace n
		on n.oid = c.relnamespace 
	where 
		c.relkind in ('r'::"char", 'p'::"char", 'v'::"char", 'm'::"char")
	union all 
	select 
		n.nspname || '.' || p.proname as obj_full_name
		, p.oid as obj_id
		, p.proname as obj_name
		, n.nspname as obj_schema
		, p.prokind as obj_type
		, 'routine'::name as obj_class
	from 
		pg_catalog.pg_proc p
	join pg_catalog.pg_namespace n
		on n.oid = p.pronamespace
) sys_obj
	on sys_obj.obj_full_name = obj_candidate.obj_name
;