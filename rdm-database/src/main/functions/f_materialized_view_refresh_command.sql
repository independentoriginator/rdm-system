create or replace function f_materialized_view_refresh_command(
	i_schema_name ${mainSchemaName}.meta_schema.internal_name%type
	, i_internal_name ${mainSchemaName}.meta_view.internal_name%type
	, i_has_unique_index boolean = false
	, i_is_populated boolean = false
)
returns text
language sql
immutable
as $function$
select 
	format(
		'refresh materialized view %s%I.%I'
		, case 
			when i_has_unique_index 
				and i_is_populated
			then 'concurrently '
			else ''
		end
		, i_schema_name 
		, i_internal_name
	) 
$function$;		

comment on function f_materialized_view_refresh_command(
	${mainSchemaName}.meta_schema.internal_name%type
	, ${mainSchemaName}.meta_view.internal_name%type
	, boolean
	, boolean
) is 'Текст команды обновления материализованного представления';