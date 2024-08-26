drop trigger if exists tr_meta_view_chunk_dependency_invalidate_view_built_flag 
on meta_view_chunk_dependency
;

create trigger tr_meta_view_chunk_dependency_invalidate_view_built_flag
after insert or update or delete
on meta_view_chunk_dependency
for each row 
execute function ${mainSchemaName}.trf_meta_view_chunk_dependency_after_update();
