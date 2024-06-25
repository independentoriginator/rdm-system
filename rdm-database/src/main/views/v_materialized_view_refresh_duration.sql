create or replace view v_materialized_view_refresh_duration
as
select
	t.meta_view_id
	, v.internal_name as meta_view_name
	, v.schema_name
	, t.start_time
	, t.end_time
	, t.end_time - t.start_time as duration 
from
	${stagingSchemaName}.materialized_view_refresh_duration t
join ${mainSchemaName}.v_meta_view v
	on t.meta_view_id = v.id
	and not v.is_disabled
order by 
	duration desc
;

comment on view v_materialized_view_refresh_duration is 'Длительность обновления материализованных представлений';