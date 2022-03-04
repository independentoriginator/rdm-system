create or replace procedure p_invalidate_type_descendants_built_flag(
	i_type_id ${mainSchemaName}.meta_type.id%type
)
language plpgsql
as $procedure$
begin
	with recursive type_descendants as (
		select
			subtype.id
		from
			ng_rdm.meta_type t
		join ng_rdm.meta_type subtype
			on subtype.super_type_id = t.id
		where 
			t.id = i_type_id
		union all 
		select 
			subtype.id
		from 
			type_descendants t
		join ng_rdm.meta_type subtype
			on subtype.super_type_id = t.id 
	)
	update ${mainSchemaName}.meta_type
	set is_built = false
	where 
		id in (select id from type_descendants)
		and is_abstract = false
	;
end
$procedure$;		