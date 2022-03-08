drop trigger if exists tr_meta_index_column_invalidate_type_built_flag on meta_index_column;
create trigger tr_meta_index_column_invalidate_type_built_flag
after insert or update or delete 
on meta_index_column
for each row 
execute function ${mainSchemaName}.trf_meta_index_column_after_update();
