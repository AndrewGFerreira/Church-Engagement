USE [RMS]


    CREATE FUNCTION RMS.[dbo].[ufnUtility_GetPrimaryPersonAliasId](@PersonId INT) 

    RETURNS int AS

    BEGIN

	    RETURN ( 
			SELECT TOP 1 [Id] FROM [PersonAlias]
			WHERE [PersonId] = @PersonId AND [AliasPersonId] = @PersonId
		)

    END




