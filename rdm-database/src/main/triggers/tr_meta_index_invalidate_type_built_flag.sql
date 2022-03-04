drop trigger if exists tr_meta_index_invalidate_type_built_flag on meta_index;
create trigger tr_meta_index_invalidate_type_built_flag
after update 
on meta_index
for each row 
execute function ${mainSchemaName}.trf_meta_index_after_update();
