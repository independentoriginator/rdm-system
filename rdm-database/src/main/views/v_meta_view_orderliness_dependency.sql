create or replace view v_meta_view_orderliness_dependency
as
-- Orderliness related dependency taking in account within parallelization
-- (in order to eliminate generated index name duplication for a partitioned table)
with 
	index_owner_name as (
		select 
			${mainSchemaName}.f_system_name_max_length() / 2 - 2 as max_len
	)
	, orderliness_dependency as (
		select
			v.schema_name
			, left(v.internal_name, n.max_len)
			, array_agg(v.id order by v.id) as view_seq
		from 
			${mainSchemaName}.v_meta_view v
		cross join index_owner_name n
		where
			v.is_matview_emulation
			and v.mv_emulation_with_partitioning
			and v.mv_emulation_chunking_field is not null 
			and not coalesce(v.is_disabled, false)
		group by
			v.schema_name
			, left(v.internal_name, n.max_len)
		having 
			count(*) > 1
	)
select 
	t.view_id
	, v.internal_name as view_name
	, v.schema_name as view_schema
	, t.master_view_id
	, mv.internal_name as master_view_name
	, mv.schema_name as master_view_schema
from (
	select
		dep.view_seq[1] as master_view_id
		, dependent_view.id as view_id
	from 
		orderliness_dependency dep
	join lateral unnest(array_remove(dep.view_seq, dep.view_seq[1])) as dependent_view(id)
		on true
	except 
	select 
		dep.master_view_id
		, dep.view_id
	from 
		${mainSchemaName}.meta_view_dependency dep
	except 
	select 
		dep.view_id
		, dep.master_view_id		
	from 
		${mainSchemaName}.meta_view_dependency dep
) t 
join ${mainSchemaName}.v_meta_view mv on mv.id = t.master_view_id
join ${mainSchemaName}.v_meta_view v on v.id = t.view_id
;

comment on view v_meta_view_orderliness_dependency is 'Метапредставления. Зависимости, связанные с упорядоченностью';