create or replace function trf_meta_view_before_update()
returns trigger
language plpgsql
as $$
begin
	new.is_created = false;

	return new;
end
$$;			
