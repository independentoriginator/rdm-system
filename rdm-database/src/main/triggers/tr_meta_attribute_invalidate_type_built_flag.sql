drop trigger if exists tr_meta_attribute_invalidate_type_built_flag on meta_attribute;
create trigger tr_meta_attribute_invalidate_type_built_flag
after update 
on meta_attribute
for each row 
execute function ${mainSchemaName}.trf_meta_attribute_after_update();
