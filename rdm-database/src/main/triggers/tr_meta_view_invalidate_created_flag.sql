drop trigger if exists tr_meta_view_invalidate_created_flag on meta_view;
create trigger tr_meta_view_invalidate_created_flag
before update 
on meta_view
for each row 
when (old.is_created = true and new.query <> old.query)
execute function ${mainSchemaName}.trf_meta_view_before_update();
