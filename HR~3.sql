SELECT object_name, status 
FROM user_objects 
WHERE object_type = 'PROCEDURE' 
AND object_name = 'PRESERVARPISTA';

SHOW ERRORS PROCEDURE PRESERVARPISTA;
