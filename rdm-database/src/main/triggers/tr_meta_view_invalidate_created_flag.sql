drop trigger if exists tr_meta_view_invalidate_created_flag on meta_view;
create trigger tr_meta_view_invalidate_created_flag
before update 
on meta_view
for each row 
when (
	old.is_created = true 
	and (
		new.query is distinct from old.query
		or new.is_matview_emulation is distinct from old.is_matview_emulation
		or new.mv_emulation_chunking_field is distinct from old.mv_emulation_chunking_field
		or new.mv_emulation_chunks_query is distinct from old.mv_emulation_chunks_query
		or new.mv_emulation_chunks_bucket_size is distinct from old.mv_emulation_chunks_bucket_size
		or new.mv_emulation_with_partitioning is distinct from old.mv_emulation_with_partitioning
	)
	and (not old.is_routine or not old.is_external)
)
execute function ${mainSchemaName}.trf_meta_view_before_update();
