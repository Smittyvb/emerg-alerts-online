port module Main exposing (..)

import Browser
import Browser.Navigation as Nav
import Html exposing (..)
import Html.Attributes exposing (class, id, href)
import Html.Events exposing (onClick, onInput)
import List
import Platform.Cmd exposing (..)
import Url
import Url.Parser as Parser exposing ((</>), Parser, map, oneOf, s, top)
import Json.Decode as D
import Json.Decode.Pipeline exposing (required, requiredAt, optional, optionalAt, hardcoded)
import Dict exposing (Dict)



-- MAIN


port updateAlerts : (D.Value -> msg) -> Sub msg

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
subscriptions model =
    updateAlerts UpdateAlerts



-- MODEL


type MsgClass
    = Heartbeat
    | SilentTest
    | ActualAlert
    | UnknownType


type MsgType
    = Alert_
    | Update
    | Cancel
    | Ack
    | Error

type MsgStatus
    = Actual
    | Exercise
    | System
    | Test
    | Draft

type MsgScope
    = Public
    -- really, we should only see Public alerts since all alerts are public in Canada
    | Restricted
    | Private

type alias AlertResource =
    { resourceDescription : String
    , mimeType : String
    , size : Maybe Int
    , uri : Maybe String
    , derefUri : Maybe String
    , digest : Maybe String
    }

type alias AlertArea =
    { areaDesc : String
    , polygon : Maybe String
    , circle : Maybe String
    , geocodes : Dict String String
    , altitude : Int
    , ceiling : Int
    }

type AlertInfoCategory
    = Geo
    | Met
    | Safety
    | Security
    | Rescue
    | Fire
    | Health
    | Env
    | Transport
    | Infra
    | CBRNE
    | Other

type AlertInfoResponseType
    = Shelter
    | Evacuate
    | Prepare
    | Execute
    | Avoid
    | Monitor
    | Assess
    | AllClear
    | None

type AlertInfoUrgency
    = Immediate
    | Expected
    | Future
    | Past
    | Unknown

type AlertInfoSeverity
    = Extreme
    | Severe
    | Moderate
    | Minor
    | UnknownSeverity

type AlertInfoCertainty
    = Observed
    -- For backward compatibility with CAP 1.0, the deprecated value of “Very Likely” SHOULD be
    -- treated as equivalent to “Likely” -- spec
    | Likely
    | Possible
    | Unlikely
    | UnknownCertainty

type alias AlertInfo =
    { language : String -- language code, if one isn't specified the standard says it's "en-US"
    , category : AlertInfoCategory
    , event : String
    , responseType : Maybe AlertInfoResponseType
    , urgency : AlertInfoUrgency
    , severity : AlertInfoSeverity
    , certainty : AlertInfoCertainty
    , audience : Maybe String
    , eventCodes : Dict String String
    , effective : Maybe String -- TODO: date
    , onset : Maybe String -- TODO: date
    , expires : Maybe String -- TODO: date
    , senderName : Maybe String
    , headline : Maybe String
    , description : Maybe String
    , instruction : Maybe String
    , web : Maybe String
    , contact : Maybe String
    , parameters : Dict String String
    , resources : List AlertResource
    , areas : List AlertArea
    }


type alias Signature =
    { digest : String
    , signature : String
    , valid : Bool
    }

type alias Alert =
    { rawXml : String
    , id : String
    , sender : String
    , sent : String -- turn into date?
    , status : MsgStatus
    , msgType : String
    , source : Maybe String
    , scope : MsgScope
    , code : List String
    , references : Maybe String
    , class : MsgClass
    , addresses : Maybe String -- since everything is public *should* never exist
    , restriction : Maybe String -- same as above
    , note : Maybe String
    , incidents : Maybe String
    , infos : List AlertInfo
    , signatures : List Signature
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


statusDecoder : D.Decoder MsgStatus
statusDecoder =
    D.string
        |> D.andThen (\str ->
           case str of
                "Actual" -> D.succeed Actual
                "Exercise" -> D.succeed Exercise
                "System" -> D.succeed System
                "Test" -> D.succeed Test
                "Draft" -> D.succeed Draft
                somethingElse ->
                    D.fail <| "Invalid status: " ++ somethingElse
        )


--alertDecoder : D.Decoder Alert
alertDecoder =
  D.succeed Alert
    |> required "rawXml" D.string
    |> requiredAt ["alert", "id"] D.string
    |> requiredAt ["alert", "sent"] D.string
    |> requiredAt ["alert", "status"] statusDecoder
    |> requiredAt ["alert", "msgType"] D.string
    |> optionalAt ["alert", "source"] D.string

init : () -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init flags url key =
    ( { alerts = []
      , connectionStatus = Connecting
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
    | UpdateAlerts D.Value


genSearchUrl : String -> String
genSearchUrl search =
    if search == "" then
        "/"

    else
        "/search/" ++ search


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

        UpdateAlerts alerts ->
            ( model
            , Cmd.none)



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
    div [ class "alert" ] [ h3 [ class "alert-title" ] [ text "todo" ] ]


subheader : String -> Html Msg
subheader title =
    h2 [ class "subheader" ] [ text title ]


alertFinderWidget : Model -> Html Msg
alertFinderWidget model =
    div [ class "alert-finder-widget" ]
        []


genAlertHtml : Alert -> Html Msg
genAlertHtml alert =
    div [] [ text "todo" ]


connectionStatusEle : Model -> Html Msg
connectionStatusEle model =
    div [ class "connection-status" ]
        [ text
            (case model.connectionStatus of
                Connecting ->
                    "Connecting..."

                Connected ->
                    "Connected"

                Delayed ->
                    "Connected, but incoming messages may be delayed"

                Reconnecting ->
                    "Disconnected, reconnecting..."

                Disconnected ->
                    "Disconnected"
            )
        ]


view : Model -> Browser.Document Msg
view model =
    { title = "AlertReady viewer"
    , body =
        [ div [ class "elm-root" ]
            [ headerEle model
            , div [ id "content" ]
                (case Parser.parse route model.url of
                    Just About ->
                        [ subheader "About" ]

                    Just Faq ->
                        [ subheader "FAQ" ]

                    Just (Search search) ->
                        List.concat
                            [ [ alertFinderWidget model ]
                            , if List.length model.alerts == 0 then
                                [ div [ class "no-alerts" ] [ text "No alerts found." ] ]

                              else
                                List.map genAlertHtml model.alerts
                            ]

                    Nothing ->
                        [ subheader "Not found" ]
                )
            ]
        ]
    }
