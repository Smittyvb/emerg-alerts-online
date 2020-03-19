module Faq exposing (faqEle)

import Html exposing (..)
import Html.Attributes exposing (..)

qa : String -> List (Html msg) -> Html msg
qa q a =
    div [ class "faq" ]
    [ div [ class "faq-q" ] [ text q ]
    , div [ class "faq-a" ] a
    ]

faqEle : Html msg
faqEle = div
    [ class "faq-root" ] 
    [ qa "What is this?" 
        [ text """
            This is a website with a list and map of emergency alerts of Canada. The emergency
            alert system is also called AlertReady or NAADS (National Alert Aggregation And
            Dissemination System).
          """
        ]
    , qa "How does the map work?"
        [ text "I'm using "
        , a [ href "http://leafletjs.com/" ] [ text "Leaflet" ]
        , text " to handle map display. Map tiles are from "
        , a [ href "TODO" ] [ text "Wikimedia Maps" ]
        , text ", which in turn gets it's underlying mapping data from "
        , a [ href "https://www.openstreetmap.org/" ] [ text "OpenStreetMap" ]
        , text "."
        ]
    , qa "What are test alerts?"
        [ text """
            This can be a bit confusing. Alerts with a status of "Test" are to ensure that the
            system is working correctly, and aren't supposed to be shown as actual alerts. However,
            twice a year there is a "Public Awareness Test" that *is* supposed to be sent to be
            sent to the public. These alerts have a status of "Actual" to ensure that they are sent
            to the public. This website shows both "Actual" and "Test" alerts, but "Test" alerts
            are filtered out by default.
          """]
    , qa "What programming language is this written in?"
        [ text "The frontend is written in "
        , a [ href "https://elm-lang.org/" ] [ text "Elm" ]
        , text " and the backend is written in "
        , a [ href "https://nodejs.org/" ] [ text "Node.js" ]
        , text "."
        ]
    ]
