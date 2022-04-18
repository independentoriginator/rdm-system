create or replace function f_meta_view_dependency_level(
	i_meta_view_id ${mainSchemaName}.meta_view.id%type
)
returns integer
language sql
stable
as $function$
select
	0 
$function$;		