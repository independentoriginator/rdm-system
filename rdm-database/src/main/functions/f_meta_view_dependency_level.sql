create or replace function f_meta_view_dependency_level(
	i_view_oid oid
)
returns integer
language sql
stable
as $function$
select 
	coalesce((
			select 
				max(${mainSchemaName}.f_meta_view_dependency_level(i_view_oid => t.master_view_oid))
			from (
				select distinct
					master_view.oid as master_view_oid
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
				where
					dependent_view.oid = i_view_oid
			) t
		) + 1,
		0
	)
$function$;		