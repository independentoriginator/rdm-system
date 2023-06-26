create or replace function f_is_db_maintenance_mode()
returns boolean
language sql
stable
as $function$
select
	exists (
		select 
			1
		from 
			${mainSchemaName}.databasechangeloglock l 
		where 
			l.locked 
			and extract(day from current_timestamp - l.lockgranted) < 1.0
		
	)
	or exists (
		select 
			1
		from 
			${mainSchemaName}.v_meta_view v
		where 
			v.is_materialized
			and not v.is_populated
			and not v.is_disabled
	)
	as is_db_maintenance_mode
;
$function$;		