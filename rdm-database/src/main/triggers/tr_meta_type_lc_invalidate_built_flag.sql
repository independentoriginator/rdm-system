drop trigger if exists tr_meta_type_lc_invalidate_built_flag on meta_type_lc;
create trigger tr_meta_type_lc_invalidate_built_flag
after insert or update or delete
on meta_type_lc
for each row 
execute function ${mainSchemaName}.trf_meta_attribute_after_update();
