drop trigger if exists tr_meta_view_invalidate_dependent_views on meta_view;
create trigger tr_meta_view_invalidate_dependent_views
after update 
on meta_view
for each row 
when ((old.is_valid = false and (new.is_valid = true or new.is_routine = true)) or (old.is_valid = true and new.is_valid = false))
execute function ${mainSchemaName}.trf_meta_view_after_refresh();
