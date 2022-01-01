create or replace view v_meta_attribute
as
with recursive attr as (
	select 
		a.id,
        t.id AS descendant_type_id,
        t.super_type_id,
        t.id as meta_type_id,
		a.internal_name,
		a.attr_type_id, 
		case when a.attr_type_id = a.meta_type_id then true else false end as is_reflective_link,
		a.length, 
		a.precision, 
		a.scale, 
		a.is_non_nullable, 
		a.is_unique, 
		a.is_localisable, 
		a.ordinal_position,
		a.default_value
	from 
		${database.defaultSchemaName}.meta_type t
	left join ${database.defaultSchemaName}.meta_attribute a on a.meta_type_id = t.id 
	union all
	select 
		a_inherited.id,
        a.descendant_type_id,
        t.super_type_id,
		a_inherited.meta_type_id,
		a_inherited.internal_name,
		a_inherited.attr_type_id, 
		case when a_inherited.attr_type_id = a_inherited.meta_type_id then true else false end as is_reflective_link,
		a_inherited.length, 
		a_inherited.precision, 
		a_inherited.scale, 
		a_inherited.is_non_nullable, 
		a_inherited.is_unique, 
		a_inherited.is_localisable, 
		a_inherited.ordinal_position,
		a_inherited.default_value
	from 
		attr a
	join ${database.defaultSchemaName}.meta_attribute a_inherited
		on a_inherited.meta_type_id = a.super_type_id
	join ${database.defaultSchemaName}.meta_type t 
		on t.id = a_inherited.meta_type_id
)
select 
	a.id,
	a.descendant_type_id as meta_type_id,
	a.internal_name,
	a.attr_type_id, 
	a.length, 
	a.precision, 
	a.scale, 
	a.is_non_nullable, 
	a.is_unique, 
	a.is_localisable, 
	a.ordinal_position,
	a.default_value,
	a.is_reflective_link
from 
	attr a
where 
	a.id is not null
;