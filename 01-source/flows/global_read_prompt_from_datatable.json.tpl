{
  "Content": {
    "Actions": [
      {
        "Identifier": "a1000000-0000-4000-8000-000000000001",
        "Parameters": {
          "DataTableId": "${data_table_cm91dGluZ19jb25maWc}",
          "Queries": [
            {
              "Attributes": [
                "GreetingText"
              ],
              "PrimaryValues": [
                {
                  "AttributeName": "ConfigKey",
                  "Value": "retail"
                }
              ],
              "QueryName": "PromptLookup"
            }
          ]
        },
        "Transitions": {
          "Errors": [
            {
              "ErrorType": "NoMatchingError",
              "NextAction": "a1000000-0000-4000-8000-000000000003"
            }
          ],
          "NextAction": "a1000000-0000-4000-8000-000000000002"
        },
        "Type": "EvaluateDataTableValues"
      },
      {
        "Identifier": "a1000000-0000-4000-8000-000000000002",
        "Parameters": {
          "Text": "$.DataTables.PromptLookup.GreetingText"
        },
        "Transitions": {
          "Errors": [
            {
              "ErrorType": "NoMatchingError",
              "NextAction": "a1000000-0000-4000-8000-000000000004"
            }
          ],
          "NextAction": "a1000000-0000-4000-8000-000000000004"
        },
        "Type": "MessageParticipant"
      },
      {
        "Identifier": "a1000000-0000-4000-8000-000000000003",
        "Parameters": {
          "Text": "Thanks for calling."
        },
        "Transitions": {
          "Errors": [
            {
              "ErrorType": "NoMatchingError",
              "NextAction": "a1000000-0000-4000-8000-000000000004"
            }
          ],
          "NextAction": "a1000000-0000-4000-8000-000000000004"
        },
        "Type": "MessageParticipant"
      },
      {
        "Identifier": "a1000000-0000-4000-8000-000000000004",
        "Parameters": {},
        "Transitions": {},
        "Type": "EndFlowModuleExecution"
      }
    ],
    "Metadata": {
      "ActionMetadata": {
        "a1000000-0000-4000-8000-000000000001": {
          "dataTableName": "${display_data_table_cm91dGluZ19jb25maWc}",
          "position": {
            "x": 160,
            "y": 80
          }
        },
        "a1000000-0000-4000-8000-000000000002": {
          "position": {
            "x": 420,
            "y": 40
          }
        },
        "a1000000-0000-4000-8000-000000000003": {
          "position": {
            "x": 420,
            "y": 220
          }
        },
        "a1000000-0000-4000-8000-000000000004": {
          "position": {
            "x": 700,
            "y": 120
          }
        }
      },
      "entryPointPosition": {
        "x": 20,
        "y": 100
      }
    },
    "Settings": {
      "InputParameters": [],
      "OutputParameters": [],
      "Transitions": [
        {
          "Description": "",
          "DisplayName": "Success",
          "ReferenceName": "Success"
        },
        {
          "Description": "",
          "DisplayName": "Error",
          "ReferenceName": "Error"
        }
      ]
    },
    "StartAction": "a1000000-0000-4000-8000-000000000001",
    "Version": "2019-10-30"
  },
  "Description": "Reads caller-facing copy from the routing_config data table so that changing what the caller hears is a data edit, not a flow deployment."
}
