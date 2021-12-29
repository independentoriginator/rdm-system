create or replace view v_meta_attribute
as
with recursive attr as (
	select 
		a.id,
		a.meta_type_id as descendant_type_id,
		a.meta_type_id,
		a.internal_name,
		a.attr_type_id, 
		a.length, 
		a.precision, 
		a.scale, 
		a.is_non_nullable, 
		a.is_unique, 
		a.is_localisable, 
		a.ordinal_position
	from 
		${database.defaultSchemaName}.meta_attribute a
	union all
	select 
		a_inherited.id,
		a.descendant_type_id,
		a_inherited.meta_type_id,
		a_inherited.internal_name,
		a_inherited.attr_type_id, 
		a_inherited.length, 
		a_inherited.precision, 
		a_inherited.scale, 
		a_inherited.is_non_nullable, 
		a_inherited.is_unique, 
		a_inherited.is_localisable, 
		a_inherited.ordinal_position
	from 
		attr a
	join ${database.defaultSchemaName}.meta_type t 
		on t.id = a.meta_type_id
	join ${database.defaultSchemaName}.meta_attribute a_inherited
		on a_inherited.meta_type_id = t.super_type_id
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
	a.ordinal_position
from 
	attr a
;