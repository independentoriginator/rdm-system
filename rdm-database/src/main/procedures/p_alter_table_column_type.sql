create or replace procedure p_alter_table_column_type(
	i_schema_name name
	, i_table_name name
	, i_column_name name
	, i_column_type varchar
)
language plpgsql
as $procedure$
declare 
	l_ddl_expr text;
	l_dependent_objs_deletion_script text[][];
	l_dependent_objs_creation_script text[][];
	l_dependent_obj text[];
begin
	select
		format('
			alter %stable %I.%I
				alter column %I set data type %s
			'
			, case when c.relkind = 'f' then 'foreign ' else '' end 
			, i_schema_name
			, i_table_name
			, i_column_name
			, i_column_type
		) 
	into
		l_ddl_expr
	from 
		pg_catalog.pg_class c
	join pg_catalog.pg_namespace s
		on s.oid = c.relnamespace
	where
		c.relname = i_table_name
		and s.nspname = i_schema_name
	;	
	
	select 
		array_agg( 
			array[
				dependent_obj.obj_schema || '.' || dependent_obj.obj_name 
				, format(
					'drop %sview %I.%I'
					, case when dependent_obj.obj_type = 'm'::"char" then 'materialized ' else '' end 
					, dependent_obj.obj_schema
					, dependent_obj.obj_name
				)
			]
			order by dependent_obj.dep_level desc
		) as dependent_objs_deletion_script
		, array_agg( 
			array[
				dependent_obj.obj_schema || '.' || dependent_obj.obj_name 
				, ${mainSchemaName}.f_view_definition(
					i_view_oid => dependent_obj.obj_oid
				)
			]
			order by dependent_obj.dep_level asc
		) as dependent_objs_creation_script
	into
		l_dependent_objs_deletion_script
		, l_dependent_objs_creation_script
	from 
		${mainSchemaName}.f_sys_obj_dependency(
			i_obj_name => i_table_name
			, i_schema_name => i_schema_name
			, i_is_routine => false
			, i_treat_the_obj_as_dependent => false
		) dependent_obj 
	where 
		dependent_obj.obj_class = 'relation'
	;	
	
	if l_dependent_objs_deletion_script is not null then
		foreach l_dependent_obj slice 1 in array l_dependent_objs_deletion_script loop
			raise notice 'Dropping the dependent object %...', l_dependent_obj[1]; 
			execute l_dependent_obj[2];
		end loop;
	end if;
		
	raise notice 'Altering the table column type %.%.%...', i_schema_name, i_table_name, i_column_name;
	execute l_ddl_expr;

	if l_dependent_objs_deletion_script is not null then
		foreach l_dependent_obj slice 1 in array l_dependent_objs_creation_script loop
			raise notice 'Recreating the dependent object %...', l_dependent_obj[1]; 
			execute l_dependent_obj[2];
		end loop;
	end if;
end
$procedure$;	

comment on procedure p_alter_table_column_type(
	name
	, name
	, name
	, varchar
) is 'Изменение типа столбца таблицы';

create or replace procedure ${stagingSchemaName}.p_alter_table_column_type(
	i_schema_name name
	, i_table_name name
	, i_column_name name
	, i_column_type varchar
)
language plpgsql
as $procedure$
begin
	call ${mainSchemaName}.p_alter_table_column_type(
		i_schema_name => i_schema_name
		, i_table_name => i_table_name
		, i_column_name => i_column_name
		, i_column_type => i_column_type
	);
end
$procedure$;			

comment on procedure ${stagingSchemaName}.p_alter_table_column_type(
	name
	, name
	, name
	, varchar
) is 'Изменение типа столбца таблицы';
