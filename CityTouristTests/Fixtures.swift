import Foundation

/// Trimmed captures of real Places API (New) responses.
enum Fixtures {

    static let nearbyLisbon = """
    {
      "places": [
        {
          "id": "place-belem-tower",
          "displayName": { "text": "Belém Tower" },
          "shortFormattedAddress": "Av. Brasília, Lisboa",
          "location": { "latitude": 38.6916, "longitude": -9.216 },
          "rating": 4.5,
          "userRatingCount": 18420,
          "priceLevel": "PRICE_LEVEL_MODERATE",
          "types": ["tourist_attraction", "historical_landmark", "point_of_interest"],
          "primaryTypeDisplayName": { "text": "Historical landmark" },
          "editorialSummary": { "text": "16th-century riverside fort." },
          "photos": [{ "name": "places/place-belem-tower/photos/AbC123" }],
          "currentOpeningHours": {
            "openNow": false,
            "weekdayDescriptions": [
              "Monday: Closed",
              "Tuesday: 9:30 AM – 6:00 PM",
              "Wednesday: 9:30 AM – 6:00 PM",
              "Thursday: 9:30 AM – 6:00 PM",
              "Friday: 9:30 AM – 6:00 PM",
              "Saturday: 10:00 AM – 7:00 PM",
              "Sunday: 10:00 AM – 5:00 PM"
            ]
          }
        },
        {
          "id": "place-time-out",
          "displayName": { "text": "Time Out Market" },
          "shortFormattedAddress": "Av. 24 de Julho, Lisboa",
          "location": { "latitude": 38.7067, "longitude": -9.1459 },
          "rating": 4.4,
          "userRatingCount": 52310,
          "priceLevel": "PRICE_LEVEL_VERY_EXPENSIVE",
          "types": ["restaurant", "food", "establishment"],
          "primaryTypeDisplayName": { "text": "Food court" },
          "photos": [{ "name": "places/place-time-out/photos/XyZ789" }],
          "currentOpeningHours": { "openNow": true }
        }
      ]
    }
    """

    /// A place missing the fields we require — must be dropped, not crash.
    static let nearbyIncomplete = """
    { "places": [
        { "displayName": { "text": "No id, no coordinates" } },
        { "id": "ok", "displayName": { "text": "Fine" },
          "location": { "latitude": 1.0, "longitude": 2.0 }, "types": ["park"] }
    ] }
    """

    static let autocompleteBarcel = """
    {
      "suggestions": [
        { "placePrediction": {
            "placeId": "city-barcelona",
            "structuredFormat": {
              "mainText": { "text": "Barcelona" },
              "secondaryText": { "text": "Spain" } } } },
        { "placePrediction": {
            "placeId": "city-barcelonnette",
            "structuredFormat": {
              "mainText": { "text": "Barcelonnette" },
              "secondaryText": { "text": "France" } } } },
        { "queryPrediction": { "text": { "text": "ignored, not a place" } } }
      ]
    }
    """

    static let cityDetailsBarcelona = """
    {
      "id": "city-barcelona",
      "displayName": { "text": "Barcelona" },
      "formattedAddress": "Barcelona, Spain",
      "location": { "latitude": 41.3874, "longitude": 2.1686 },
      "photos": [{ "name": "places/city-barcelona/photos/CoverPhoto" }]
    }
    """

    static let permissionDenied = """
    { "error": { "code": 403, "message": "Places API has not been used in project",
                 "status": "PERMISSION_DENIED" } }
    """
}
