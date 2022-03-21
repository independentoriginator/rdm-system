drop trigger if exists tr_meta_attribute_lc_invalidate_type_built_flag on meta_attribute_lc;
create trigger tr_meta_attribute_lc_invalidate_type_built_flag
after insert or update or delete
on meta_attribute_lc
for each row 
execute function ${mainSchemaName}.trf_meta_attribute_after_update();
