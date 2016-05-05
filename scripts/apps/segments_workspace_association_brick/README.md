Semgment-Client association brick
===========
This brick provides you way to define association between segments and clients.

## Key Features:
From a high level perspective this brick can do for you

- Add/remove clients from segments
- Move clients between segments
- Allows to specify fo additional technical segment/workspace to be merged in

## What you need to get started:
- an organization and an organization admin (for getting those contact our support)
- whitelabeled domain (bascically you need gd to set up your own hostname for you. If you do not have this it will not work)


## Setting association

This brick is very simple you need to provide it with the segment-workspace association and you are done. 

### segment workspace association file

As usual it takes any of the sources described here. In general it will be a file that by default should look like this


  client_id   |  segment_id    | project_id         
--------------|----------------|--------------------
  client_1    |   segment_1    | asdsandmansdjahsdi 
  client_2    |   segment_1    | lasdiuoiasdiuqwhef 

Keep in mind that as in all other bricks the information is expected to be provided declaratively. What is there will be provisioned/moved (or kept if already present) what is not mentioned will be removed if present.


#### Deployment parameters

To use that file the parameters to be passed look like this (Here we assume the file is on the project storage). 

  	{
      "organization": "organization_name",
      "input_source" : "file_name.csv"
    }

### Adding a technical client
In some cases need might arrise to have additional project to host ETLs or anything else. Information about these clients will not come from the provider of the data since the definition is delcarative the only way to get areound that is to process the data and add the additional information to it. The brick provides you with this functionality for convenience. You can use the following params to enable this.

  	{
      "organization": "organization_name",
      "input_source" : "file_name.csv",
      "technical_client" : { segment_id: 'segment_test_brick', client_id: 'gd_technical_client' }
    }

You can even specify several if that is what you need

  	{
      "organization": "organization_name",
      "input_source" : "file_name.csv",
      "technical_client" : [
        { segment_id: 'segment_test_brick', client_id: 'gd_technical_client_1' },
        { segment_id: 'segment_test_brick', client_id: 'gd_technical_client_2' }
      ]
    }

Take note that the technical client does not follow your custom column specifiers. It always has to be segment_id/client_id.

#### Column name defaults
The following list summarizes the default column names. The name after hyphen is the default. In parenthesis you can find name of the parameter you can use to override the default.

* Client ID - client_id (client_id_column)
* Segment ID - segment_id (segment_id_column)
* Project ID - project_id (project_id_column)

For instance, if in your segment id would be stored in a column called "x", you would pass as param something along the lines of

    {
      "segment_id_column": "x"
    }

![Updating user in organization](https://www.dropbox.com/s/y5betor6loa6bn3/updating_user_in_org.png?dl=0&raw=1)

Notice that while john's email was updated his first name was not.

### Notes
* Usually you will not provide the project_id in your file. It is mentioned here for completness. If not mentioned the associated project will be preserved. If not there it will not be created. For project provisioning there is a separate brick.

