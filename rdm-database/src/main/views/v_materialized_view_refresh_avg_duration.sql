drop view if exists v_materialized_view_refresh_avg_duration;

create view v_materialized_view_refresh_avg_duration
as
with 
	stat as (
		select
			meta_view_id
			, meta_view_name
			, schema_name
			, start_time
			, end_time
			, duration
			, last_value(duration) 
				over(
					partition by 
						meta_view_id 
					order by 
						start_time 
					range between 
			            unbounded preceding and 
			            unbounded following						
				) as last_duration			
		from 
			${mainSchemaName}.v_materialized_view_refresh_duration
	)
select
	meta_view_id
	, meta_view_name
	, schema_name
	, avg(duration) as avg_duration
	, max(end_time) as last_time
	, max(last_duration) as last_duration 
	, to_char(
		(
			extract('epoch' from max(last_duration)) / 
				extract('epoch' from avg(duration))
			- 1.0
		) * 100
		,'FM9999%'
	) as degradation
from
	stat
group by 
	meta_view_id
	, meta_view_name
	, schema_name
order by 
	avg_duration desc
;

comment on view v_materialized_view_refresh_avg_duration is 'Средняя длительность обновления материализованных представлений';