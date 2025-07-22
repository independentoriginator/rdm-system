drop procedure if exists 
	p_alter_table_column_type(
		name
		, name
		, name
		, varchar
	)
;

drop procedure if exists 
	p_alter_table_column_type(
		name
		, name
		, name
		, varchar
		, boolean
	)
;

create or replace procedure 
	p_alter_table_column_type(
		i_schema_name name
		, i_table_name name
		, i_column_name name
		, i_column_type varchar
		, i_defer_dependent_obj_recreation boolean = false -- calling p_perform_deferred_dependent_obj_rebuild before the session completion is expected
		, i_enforce_nodata_for_dependent_matview_being_recreated boolean = false
	)
language plpgsql
as $procedure$
declare 
	l_ddl_sttmnt text
	;
begin
	select
		format('
			alter %stable %I.%I
				alter column %I set data type %s%s
			'
			, case when c.relkind = 'f' then 'foreign ' else '' end 
			, i_schema_name
			, i_table_name
			, i_column_name
			, i_column_type
			, case
				when c.relkind <> 'f' then
					 format(
					 	' using %I::%s'
						, i_column_name
						, i_column_type
					)
				else 
					''
			end
		) 
	into
		l_ddl_sttmnt
	from 
		pg_catalog.pg_class c
	join pg_catalog.pg_namespace s
		on s.oid = c.relnamespace
	where
		c.relname = i_table_name
		and s.nspname = i_schema_name
	;	

	call 
		${mainSchemaName}.p_alter_obj_with_dep_obj_recreation(
			i_obj_name => i_table_name
			, i_obj_schema => i_schema_name
			, i_obj_class => 'relation'
			, i_ddl_sttmnt => i_ddl_sttmnt
			, i_defer_dependent_obj_recreation => i_defer_dependent_obj_recreation
			, i_enforce_nodata_for_dependent_matview_being_recreated => i_enforce_nodata_for_dependent_matview_being_recreated
		)
	;
end
$procedure$
;	

comment on procedure 
	p_alter_table_column_type(
		name
		, name
		, name
		, varchar
		, boolean
		, boolean
	) 
	is 'Изменение типа столбца таблицы'
;

drop procedure if exists 
	${stagingSchemaName}.p_alter_table_column_type(
		name
		, name
		, name
		, varchar
	)
;

drop procedure if exists 
	${stagingSchemaName}.p_alter_table_column_type(
		name
		, name
		, name
		, varchar
		, boolean
	)
;

create or replace procedure 
	${stagingSchemaName}.p_alter_table_column_type(
		i_schema_name name
		, i_table_name name
		, i_column_name name
		, i_column_type varchar
		, i_defer_dependent_obj_recreation boolean = false
		, i_enforce_nodata_for_dependent_matview_being_recreated boolean = false
	)
language plpgsql
as $procedure$
begin
	call 
		${mainSchemaName}.p_alter_table_column_type(
			i_schema_name => i_schema_name
			, i_table_name => i_table_name
			, i_column_name => i_column_name
			, i_column_type => i_column_type
			, i_defer_dependent_obj_recreation => i_defer_dependent_obj_recreation
			, i_enforce_nodata_for_dependent_matview_being_recreated => i_enforce_nodata_for_dependent_matview_being_recreated
		)
	;
end
$procedure$
;			

comment on procedure 
	${stagingSchemaName}.p_alter_table_column_type(
		name
		, name
		, name
		, varchar
		, boolean
		, boolean
	) 
	is 'Изменение типа столбца таблицы'
;
