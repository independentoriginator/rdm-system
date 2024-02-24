create or replace function f_target_routine_name(
	i_target_routine_id oid
)
returns text
language sql
volatile
as $function$
set local search_path = pg_catalog;
select
	regexp_replace(i_target_routine_id::regprocedure::text, '(.+)\.(.+)(\(.*\))', '\2\3')
$function$;		

comment on function f_target_routine_name(
	oid
) is 'Целевое имя процедуры/функции для регистрации в метаданных';