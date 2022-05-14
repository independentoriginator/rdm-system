create or replace function f_view_definition(
	i_view_oid oid
)
returns text
language sql
stable
as $function$
select
	format(
		$$CREATE %s VIEW %I.%I AS %s%s%s%s%s$$
		, case c.relkind when 'm'::char then 'MATERIALIZED' else '' end
		, ns.nspname
		, c.relname
		, E'\n' || pg_catalog.pg_get_viewdef(c.oid)
		, format(
			E'\n' || $comment$COMMENT ON %s VIEW %I.%I IS $c$%s$c$;$comment$
			, case c.relkind when 'm'::char then 'MATERIALIZED' else '' end
			, ns.nspname
			, c.relname
			, d.description
		)
		, (
			select 
				E'\n' || array_to_string(
					array_agg(
						format(
							$comment$COMMENT ON COLUMN %I.%I.%s IS $c$%s$c$;$comment$
							, ns.nspname
							, c.relname
							, a.attname
							, ad.description
						)
						order by a.attnum
					), 
					E'\n'
				)
			from 
				pg_catalog.pg_attribute a 
			join pg_description ad
				on ad.objoid = a.attrelid 
				and ad.objsubid = a.attnum
			where 
				a.attrelid = c.oid
				and a.attnum > 0
		)
		, (
			select 
				E'\n' || array_to_string(
					array_agg(
						format(
							'GRANT %s ON %I.%I TO %s;'
							, g.privilege_type 
							, g.table_schema 
							, g.table_name 
							, g.grantee 
						)
					), 
					E'\n'
				)
			from 
				information_schema.role_table_grants g
			where 
				g.table_name = c.relname
				and g.table_schema = ns.nspname
		)
		, (
			select 
				E'\n' || array_to_string(
					array_agg(
						i.indexdef || ';'
					), 
					E'\n'
				)
			from 
				pg_catalog.pg_indexes i
			where 
				i.tablename = c.relname
				and i.schemaname = ns.nspname 
		)
	)
from 
	pg_catalog.pg_class c
join pg_catalog.pg_namespace ns
	on ns.oid = c.relnamespace
left join pg_description d
	on d.objoid = c.oid 
	and d.objsubid = 0
where 
	c.oid = i_view_oid
;
$function$;		