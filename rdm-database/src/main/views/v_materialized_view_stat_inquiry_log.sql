drop view if exists v_materialized_view_stat_inquiry_log
;
create or replace view v_materialized_view_stat_inquiry_log
as
select
	t.stat_inquiring_view_id
	, v.internal_name as matview_name
	, v.schema_name as matview_schema
	, t.stat_inquiry_time
	, coalesce(underlying_type.internal_name, underlying_matview.internal_name) as underlying_table_name
	, coalesce(underlying_type.schema_name, underlying_matview.schema_name) as underlying_table_schema
	, coalesce(t_upd_log.update_time, mv_upd_log.update_time) as last_explicit_stat_update_time
	, t.stat_update_time as actual_stat_update_time
	, t.stat_autoupdate_time as actual_stat_autoupdate_time
	, case 
		when coalesce(t_upd_log.update_time, mv_upd_log.update_time) > greatest(t.stat_update_time, t.stat_autoupdate_time)
			or (
				t.stat_update_time is null
				and t.stat_autoupdate_time is null 
			)
		then true
		else false
	end as is_statistics_inactual
from
	${stagingSchemaName}.matview_stat_inquiry_log t
join ${mainSchemaName}.v_meta_view v
	on v.id = t.stat_inquiring_view_id
	and not v.is_disabled
left join ${mainSchemaName}.v_meta_type underlying_type
	on underlying_type.id = t.meta_type_id
left join ${mainSchemaName}.v_meta_view underlying_matview
	on underlying_matview.id = t.meta_view_id
left join lateral (
	select 
		upd_log.update_time
	from 
		${stagingSchemaName}.table_stat_explicit_update_log upd_log
	where 
		upd_log.meta_type_id = t.meta_type_id
		and upd_log.update_time <= t.stat_inquiry_time
	order by 
		upd_log.update_time
	limit 
		1
) t_upd_log
	on true
left join lateral (
	select 
		upd_log.update_time
	from 
		${stagingSchemaName}.matview_stat_explicit_update_log upd_log
	where 
		upd_log.meta_view_id = t.meta_view_id
		and upd_log.update_time <= t.stat_inquiry_time
	order by 
		upd_log.update_time
	limit 
		1
) mv_upd_log
	on true
order by 
	t.stat_inquiry_time desc
;

comment on view v_materialized_view_stat_inquiry_log is 'Журнал проверки актуальности статистики при обновлении материализованных представлений';