create or replace view v_materialized_view_pending_refresh
as
select
	v.id
	, v.internal_name
	, v.schema_id
	, v.schema_name
	, v.dependency_level
	, v.creation_order
	, v.is_external
	, v.is_populated
	, v.refresh_time
	, v.modification_time
	, (
		v.refresh_time is null
		or v.refresh_time < v.modification_time 
	) as is_recreated
from
	${mainSchemaName}.v_meta_view v
where 
	v.is_materialized
	and not v.is_valid
	and not v.is_disabled
	and v.is_created
order by 	
	v.dependency_level
;

comment on view v_materialized_view_pending_refresh is 'Материализованные представления, ожидающие обновления';