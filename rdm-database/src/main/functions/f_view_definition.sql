create or replace function f_view_definition(
	i_view_oid pg_catalog.pg_class.oid%type
	, i_enforce_nodata_for_matview boolean = false
)
returns text
language plpgsql
stable
as $function$
declare 
	l_view_name pg_catalog.pg_class.relname%type;
	l_schema_name pg_catalog.pg_namespace.nspname%type;
	l_view_type pg_catalog.pg_class.relkind%type;
	l_description pg_catalog.pg_description.description%type;
	l_view_def text;
begin
	select
		c.relname 
		, ns.nspname
		, c.relkind
		, d.description
	into
		l_view_name
		, l_schema_name
		, l_view_type
		, l_description
	from 
		pg_catalog.pg_class c
	join pg_catalog.pg_namespace ns
		on ns.oid = c.relnamespace
	left join pg_catalog.pg_description d
		on d.objoid = c.oid 
		and d.objsubid = 0
	where 
		c.oid = i_view_oid
	;
	
	l_view_def := pg_catalog.pg_get_viewdef(i_view_oid);
	
	if l_view_type = 'm'::char and i_enforce_nodata_for_matview then
		l_view_def := regexp_replace(l_view_def, ';$', '') || ' WITH NO DATA;'; 
	end if;
		
	return
		format(
			$$CREATE %s VIEW %I.%I AS %s%s%s%s%s$$
			, case l_view_type when 'm'::char then 'MATERIALIZED' else '' end
			, l_schema_name
			, l_view_name
			, E'\n' || l_view_def
			, format(
				E'\n' || $comment$COMMENT ON %s VIEW %I.%I IS $c$%s$c$;$comment$
				, case l_view_type when 'm'::char then 'MATERIALIZED' else '' end
				, l_schema_name
				, l_view_name
				, l_description
			)
			, (
				select 
					E'\n' || array_to_string(
						array_agg(
							format(
								$comment$COMMENT ON COLUMN %I.%I.%s IS $c$%s$c$;$comment$
								, l_schema_name
								, l_view_name
								, a.attname
								, d.description
							)
							order by a.attnum
						), 
						E'\n'
					)
				from 
					pg_catalog.pg_attribute a 
				join pg_catalog.pg_description d
					on d.objoid = a.attrelid 
					and d.objsubid = a.attnum
				where 
					a.attrelid = i_view_oid
					and a.attnum > 0
			)
			, (
				select 
					E'\n' || array_to_string(
						array_agg(
							format(
								'GRANT %s ON %I.%I TO %s%s;'
								, g.privilege_type 
								, g.table_schema 
								, g.table_name 
								, g.grantee 
								, case when g.is_grantable = 'YES' then ' WITH GRANT OPTION' else '' end
							)
						), 
						E'\n'
					)
				from 
					information_schema.role_table_grants g
				where 
					g.table_name = l_view_name
					and g.table_schema = l_schema_name
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
					i.tablename = l_view_name
					and i.schemaname = l_schema_name 
			)
		)
	;
end
$function$;

comment on function f_view_definition(
	pg_catalog.pg_class.oid%type
	, boolean
) is 'Определение представления';