{
  "Content": {
    "Actions": [
      {
        "Identifier": "b2000000-0000-4000-8000-000000000001",
        "Parameters": {
          "Text": "Sorry, we cannot take your call right now. Please try again later."
        },
        "Transitions": {
          "Errors": [
            {
              "ErrorType": "NoMatchingError",
              "NextAction": "b2000000-0000-4000-8000-000000000002"
            }
          ],
          "NextAction": "b2000000-0000-4000-8000-000000000002"
        },
        "Type": "MessageParticipant"
      },
      {
        "Identifier": "b2000000-0000-4000-8000-000000000002",
        "Parameters": {},
        "Transitions": {},
        "Type": "DisconnectParticipant"
      }
    ],
    "Metadata": {
      "ActionMetadata": {
        "b2000000-0000-4000-8000-000000000001": {
          "position": {
            "x": 160,
            "y": 80
          }
        },
        "b2000000-0000-4000-8000-000000000002": {
          "position": {
            "x": 440,
            "y": 80
          }
        }
      },
      "entryPointPosition": {
        "x": 20,
        "y": 100
      }
    },
    "StartAction": "b2000000-0000-4000-8000-000000000001",
    "Version": "2019-10-30"
  },
  "Description": "Fallback flow. Reached from the main flow via a DYNAMIC reference read from the data table at contact time, which is what avoids a Terraform dependency cycle and a second apply.",
  "Type": "CONTACT_FLOW"
}
