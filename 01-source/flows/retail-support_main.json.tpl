{
  "Content": {
    "Actions": [
      {
        "Identifier": "c3000000-0000-4000-8000-000000000001",
        "Parameters": {
          "FlowLoggingBehavior": "Enabled"
        },
        "Transitions": {
          "Errors": [],
          "NextAction": "c3000000-0000-4000-8000-000000000002"
        },
        "Type": "UpdateFlowLoggingBehavior"
      },
      {
        "Identifier": "c3000000-0000-4000-8000-000000000002",
        "Parameters": {
          "DataTableId": "${data_table_cm91dGluZ19jb25maWc}",
          "Queries": [
            {
              "Attributes": [
                "QueueId",
                "FallbackFlowId",
                "GreetingText"
              ],
              "PrimaryValues": [
                {
                  "AttributeName": "ConfigKey",
                  "Value": "retail"
                }
              ],
              "QueryName": "RoutingLookup"
            }
          ]
        },
        "Transitions": {
          "Errors": [
            {
              "ErrorType": "NoMatchingError",
              "NextAction": "c3000000-0000-4000-8000-000000000006"
            }
          ],
          "NextAction": "c3000000-0000-4000-8000-000000000003"
        },
        "Type": "EvaluateDataTableValues"
      },
      {
        "Identifier": "c3000000-0000-4000-8000-000000000003",
        "Parameters": {
          "FlowModuleId": "${flow_module_Z2xvYmFsX3JlYWRfcHJvbXB0X2Zyb21fZGF0YXRhYmxl}"
        },
        "Transitions": {
          "Errors": [
            {
              "ErrorType": "NoMatchingError",
              "NextAction": "c3000000-0000-4000-8000-000000000004"
            }
          ],
          "NextAction": "c3000000-0000-4000-8000-000000000004"
        },
        "Type": "InvokeFlowModule"
      },
      {
        "Identifier": "c3000000-0000-4000-8000-000000000004",
        "Parameters": {
          "QueueId": "${queue_cmV0YWlsLXByaW9yaXR5X2Vu}"
        },
        "Transitions": {
          "Errors": [
            {
              "ErrorType": "NoMatchingError",
              "NextAction": "c3000000-0000-4000-8000-000000000006"
            }
          ],
          "NextAction": "c3000000-0000-4000-8000-000000000005"
        },
        "Type": "UpdateContactTargetQueue"
      },
      {
        "Identifier": "c3000000-0000-4000-8000-000000000005",
        "Parameters": {},
        "Transitions": {
          "Errors": [
            {
              "ErrorType": "NoMatchingError",
              "NextAction": "c3000000-0000-4000-8000-000000000006"
            },
            {
              "ErrorType": "QueueAtCapacity",
              "NextAction": "c3000000-0000-4000-8000-000000000006"
            }
          ],
          "NextAction": "c3000000-0000-4000-8000-000000000007"
        },
        "Type": "TransferContactToQueue"
      },
      {
        "Identifier": "c3000000-0000-4000-8000-000000000006",
        "Parameters": {
          "ContactFlowId": "$.DataTables.RoutingLookup.FallbackFlowId"
        },
        "Transitions": {
          "Errors": [
            {
              "ErrorType": "NoMatchingError",
              "NextAction": "c3000000-0000-4000-8000-000000000007"
            }
          ],
          "NextAction": "c3000000-0000-4000-8000-000000000007"
        },
        "Type": "TransferToFlow"
      },
      {
        "Identifier": "c3000000-0000-4000-8000-000000000007",
        "Parameters": {},
        "Transitions": {},
        "Type": "DisconnectParticipant"
      }
    ],
    "Metadata": {
      "ActionMetadata": {
        "c3000000-0000-4000-8000-000000000001": {
          "position": {
            "x": 160,
            "y": 100
          }
        },
        "c3000000-0000-4000-8000-000000000002": {
          "dataTableName": "${display_data_table_cm91dGluZ19jb25maWc}",
          "position": {
            "x": 400,
            "y": 100
          }
        },
        "c3000000-0000-4000-8000-000000000003": {
          "position": {
            "x": 660,
            "y": 100
          }
        },
        "c3000000-0000-4000-8000-000000000004": {
          "position": {
            "x": 920,
            "y": 60
          },
          "queue": {
            "text": "${display_queue_cmV0YWlsLXByaW9yaXR5X2Vu}"
          }
        },
        "c3000000-0000-4000-8000-000000000005": {
          "position": {
            "x": 1180,
            "y": 60
          }
        },
        "c3000000-0000-4000-8000-000000000006": {
          "position": {
            "x": 920,
            "y": 300
          }
        },
        "c3000000-0000-4000-8000-000000000007": {
          "position": {
            "x": 1440,
            "y": 180
          }
        }
      },
      "entryPointPosition": {
        "x": 20,
        "y": 120
      }
    },
    "StartAction": "c3000000-0000-4000-8000-000000000001",
    "Version": "2019-10-30"
  },
  "Description": "Main inbound flow. Mixes both reference strategies on purpose: the data table and flow module are substituted at DEPLOY time, while the fallback flow is resolved at CONTACT time. The working queue is deliberately WRONG (retail-priority_en) so there is something for a designer to fix in the console.",
  "Type": "CONTACT_FLOW"
}
