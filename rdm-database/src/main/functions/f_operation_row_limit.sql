create or replace function f_operation_row_limit()
returns bigint
language sql
immutable
parallel safe
as $function$
select 
	${operation_row_limit}::bigint
$function$;		

comment on function f_operation_row_limit(
) is 'Ограничение на количество обрабатываемых строк для операции';