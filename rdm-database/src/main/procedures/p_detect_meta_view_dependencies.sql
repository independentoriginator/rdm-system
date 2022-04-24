create or replace procedure p_detect_meta_view_dependencies(
	i_internal_name ${mainSchemaName}.meta_view.internal_name%type
	, i_schema_name ${mainSchemaName}.meta_schema.internal_name%type
)
language plpgsql
as $procedure$
begin
	insert into ${mainSchemaName}.meta_view_dependency(
		view_id
		, master_view_id
		, level
	)
	
	with recursive dependency(cls_name, cls_schema, cls_relkind, level) as (
		select i_schema_name, i_internal_name, null::"char", 0
		union
		select 
			dep.dependent_cls_name
			, dep.dependent_cls_schema
			, dep.dependent_cls_relkind
			, dependency.levele + 1
		from 
			${mainSchemaName}.v_sys_obj_dependency dep
		join dependency 
			on dependency.master_cls_name = dependency.cls_name
			and dependency.master_cls_schema = dependency.cls_schema
	)
	select 
	
	from 
		dependency
	where
		
	
	dependent_cls.oid as dependent_cls_oid
	, dependent_cls.relname as dependent_cls_name
	, dependent_cls_ns.nspname as dependent_cls_schema
	, dependent_cls.relkind as dependent_cls_relkind
	, master_cls.oid as master_cls_oid
	, master_cls.relname as master_cls_name
	, master_cls_ns.nspname as master_cls_schema
	, master_cls.relkind as master_cls_relkind
			
			
	select distinct
		dependent_view.oid as dependent_view_oid
		, dependent_view.relname as dependent_view_name
		, master_view.oid as master_view_oid
		, master_view.relname as master_view_name
	from
		pg_catalog.pg_class dependent_view
	join pg_catalog.pg_rewrite pg_rewrite
		on pg_rewrite.ev_class = dependent_view.oid
	join pg_catalog.pg_depend pg_depend
		on pg_depend.objid = pg_rewrite.oid
	join pg_catalog.pg_class master_view 
		on master_view.oid = pg_depend.refobjid
		and master_view.relkind = 'm'::char
		and master_view.oid <> dependent_view.oid	
	;
		
end
$procedure$;			
