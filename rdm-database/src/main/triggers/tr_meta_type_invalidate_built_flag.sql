drop trigger if exists tr_meta_type_invalidate_built_flag on meta_type;
create trigger tr_meta_type_invalidate_built_flag
before update 
on meta_type
for each row 
when (old.is_built = true)
execute function ${mainSchemaName}.trf_meta_type_before_update();
