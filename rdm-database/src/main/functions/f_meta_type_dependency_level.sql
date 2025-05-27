create or replace function 
	f_meta_type_dependency_level(
		i_meta_type_id ${mainSchemaName}.meta_type.id%type
	)
returns integer
language sql
stable
as $function$
with recursive
	meta_type as (
		select 
			i_meta_type_id as id
			, 0::integer as n_level
			, array[i_meta_type_id] as dep_seq 
		union all
		select 
			referenced_type.id 
			, dependent_type.n_level + 1 as n_level
			, dependent_type.dep_seq || referenced_type.id as dep_seq 
		from 
			meta_type dependent_type
		join lateral (
			select distinct
				referenced_type.id as id
			from 
				${mainSchemaName}.meta_attribute a 
			join ${mainSchemaName}.meta_type referenced_type 
				on referenced_type.id = a.attr_type_id 
				and referenced_type.is_primitive = false
			where 
				a.master_id = dependent_type.id
			union 
			select 
				t.master_type_id as id
			from 
				${mainSchemaName}.meta_type t 
			where 
				t.id = dependent_type.id
				and t.master_type_id is not null
				and t.master_type_id <> t.id
		) referenced_type
			on referenced_type.id <> all(dependent_type.dep_seq)
	)
select 
	max(n_level)
from 
	meta_type
$function$
;

comment on function 
	f_meta_type_dependency_level(
		${mainSchemaName}.meta_type.id%type
	) 
	is 'Уровень зависимости метатипа'
;