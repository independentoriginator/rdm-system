create or replace procedure p_invalidate_type_descendants_built_flag(
	i_type_id ${mainSchemaName}.meta_type.id%type
)
language plpgsql
as $procedure$
begin
	with recursive 
		type_descendants as (
			select
				subtype.id
			from
				${mainSchemaName}.meta_type t
			join ${mainSchemaName}.meta_type subtype
				on subtype.super_type_id = t.id
			where 
				t.id = i_type_id
			union all 
			select 
				subtype.id
			from 
				type_descendants t
			join ${mainSchemaName}.meta_type subtype
				on subtype.super_type_id = t.id 
		)
		, meta_type_descendants as (
			select 
				t.id
			from 
				${mainSchemaName}.meta_type t
			join type_descendants d 
				on d.id = t.id
			where 
				t.is_built = true
				and t.is_abstract = false
			order by 
				t.id
			for update of t
		)
	update 
		${mainSchemaName}.meta_type t
	set 
		is_built = false
	from 
		meta_type_descendants d
	where 
		t.id = d.id
	;
end
$procedure$;

comment on procedure p_invalidate_type_descendants_built_flag(
	${mainSchemaName}.meta_type.id%type
) is 'Выставить флаг необходимости перестроения у зависимых типов указанного метатипа';