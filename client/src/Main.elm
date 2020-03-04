module Main exposing (..)

import Browser
import Browser.Navigation as Nav
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput)
import Platform.Cmd exposing (..)
import Url
import Url.Parser as Parser exposing ((</>), Parser, map, oneOf, s, top)



-- MAIN


main : Program () Model Msg
main =
    Browser.application
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        , onUrlChange = UrlChanged
        , onUrlRequest = LinkClicked
        }



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none



-- MODEL


type alias Alert =
    { rawXml : String
    , title : String
    }


type ConnectionStatus
    = Connecting
    | Connected
    | Delayed -- heartbeats aren't coming through
    | Reconnecting
    | Disconnected


type alias Model =
    { alerts : List Alert
    , connectionStatus : ConnectionStatus
    , lastUpdate : Int
    , key : Nav.Key
    , url : Url.Url
    , search : String
    }


init : () -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init flags url key =
    ( { alerts = []
      , connectionStatus = Connected
      , lastUpdate = 0
      , key = key
      , url = url
      , search = ""
      }
    , Cmd.none
    )


type Msg
    = LinkClicked Browser.UrlRequest
    | UrlChanged Url.Url
    | SearchChange String


genSearchUrl : String -> String
genSearchUrl search =
    if search == "" then
        "/"

    else
        "search/" ++ search


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SearchChange search ->
            ( model, Nav.pushUrl model.key (genSearchUrl search) )

        LinkClicked urlRequest ->
            case urlRequest of
                Browser.Internal url ->
                    ( model, Nav.pushUrl model.key (Url.toString url) )

                Browser.External href ->
                    ( model, Nav.load href )

        UrlChanged url ->
            ( { model | url = url }
            , Cmd.none
            )



-- VIEW


websiteName : String
websiteName =
    "alerts.test"


viewLink : String -> String -> Html msg
viewLink name path =
    a [ href path, class "header-link" ] [ text name ]


headerEle : Model -> Html Msg
headerEle model =
    header []
        [ h1 [ id "header-title" ]
            [ viewLink websiteName "/"
            ]
        , viewLink "FAQ" "/faq"
        , viewLink "About" "/about"
        ]


type Route
    = Search String
    | About
    | Faq


route : Parser (Route -> a) a
route =
    oneOf
        [ Parser.map (Search "") top
        , Parser.map Search (Parser.s "search" </> Parser.string)
        , Parser.map About (Parser.s "about")
        , Parser.map Faq (Parser.s "faq")
        , Parser.map Search (Parser.s "alert" </> Parser.string)
        ]


alertDiv : Alert -> Html Msg
alertDiv alert =
    div [ class "alert" ] [ text alert.title ]


subheader : String -> Html Msg
subheader title =
    h2 [ class "subheader" ] [ text title ]


view : Model -> Browser.Document Msg
view model =
    { title = "AlertReady viewer"
    , body =
        [ div [ class "elm-root" ]
            [ headerEle model
            , div []
                (case Parser.parse route model.url of
                    Just About ->
                        [ subheader "About" ]

                    Just Faq ->
                        [ subheader "FAQ" ]

                    Just (Search search) ->
                        [ input [ value search, placeholder "Find an alert ID", onInput SearchChange ] []
                        , alertDiv { rawXml = "", title = "Alert title" }
                        ]

                    Nothing ->
                        [ subheader "Not found" ]
                )
            ]
        ]
    }
