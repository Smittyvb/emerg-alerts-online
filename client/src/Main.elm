port module Main exposing (updateAlerts, updateConnectionStatus)

import Browser
import Browser.Navigation as Nav
import Debug exposing (log)
import Dict exposing (Dict)
import Html exposing (..)
import Html.Attributes exposing (class, href, id)
import Html.Lazy exposing (lazy2)
import Json.Decode as D
import Json.Decode.Pipeline exposing (custom, hardcoded, required, requiredAt)
import List
import Url
import Url.Parser as Parser exposing ((</>), Parser, map, oneOf, s, top)



-- MAIN


port updateAlerts : (D.Value -> msg) -> Sub msg
port updateConnectionStatus : (String -> msg) -> Sub msg


type alias FlagData =
    { language : String
    }


main : Program FlagData Model Msg
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
    Sub.batch
    [ updateAlerts UpdateAlerts
    , updateConnectionStatus UpdateConnectionStatus
    ]



-- MODEL


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
    , msgType : MsgType
    , source : Maybe String
    , scope : MsgScope
    , code : List String
    , references : Maybe String
    , addresses : Maybe String -- since everything is public *should* never exist
    , restriction : Maybe String -- same as above
    , note : Maybe String
    , incidents : Maybe String
    , infos : List AlertInfo
    , signatures : List Signature
    }


type AlertOrError
    = SomeAlert Alert
    | InvalidAlert String


type ConnectionStatus
    = Connecting
    | Connected
    | Delayed -- heartbeats aren't coming through
    | Reconnecting
    | Disconnected


type alias Model =
    { alerts : List AlertOrError
    , connectionStatus : ConnectionStatus
    , lastUpdate : Int
    , key : Nav.Key
    , url : Url.Url
    , search : String
    , language : String
    }


statusDecoder : D.Decoder MsgStatus
statusDecoder =
    D.string
        |> D.andThen
            (\str ->
                case str of
                    "Actual" ->
                        D.succeed Actual

                    "Exercise" ->
                        D.succeed Exercise

                    "System" ->
                        D.succeed System

                    "Test" ->
                        D.succeed Test

                    "Draft" ->
                        D.succeed Draft

                    somethingElse ->
                        D.fail <| "Invalid status: " ++ somethingElse
            )


scopeDecoder : D.Decoder MsgScope
scopeDecoder =
    D.string
        |> D.andThen
            (\str ->
                case str of
                    "Public" ->
                        D.succeed Public

                    "Restricted" ->
                        D.succeed Restricted

                    "Private" ->
                        D.succeed Private

                    somethingElse ->
                        D.fail <| "Invalid scope: " ++ somethingElse
            )


typeDecoder : D.Decoder MsgType
typeDecoder =
    D.string
        |> D.andThen
            (\str ->
                case str of
                    "Alert" ->
                        D.succeed Alert_

                    "Update" ->
                        D.succeed Update

                    "Cancel" ->
                        D.succeed Cancel

                    "Ack" ->
                        D.succeed Ack

                    "Error" ->
                        D.succeed Error

                    somethingElse ->
                        D.fail <| "Invalid type: " ++ somethingElse
            )


infoCategoryDecoder : D.Decoder AlertInfoCategory
infoCategoryDecoder =
    D.string
        |> D.andThen
            (\str ->
                case str of
                    "Geo" ->
                        D.succeed Geo

                    "Met" ->
                        D.succeed Met

                    "Safety" ->
                        D.succeed Safety

                    "Security" ->
                        D.succeed Security

                    "Rescue" ->
                        D.succeed Rescue

                    "Fire" ->
                        D.succeed Fire

                    "Health" ->
                        D.succeed Health

                    "Env" ->
                        D.succeed Env

                    "Transport" ->
                        D.succeed Transport

                    "Infra" ->
                        D.succeed Infra

                    "CBRNE" ->
                        D.succeed CBRNE

                    "Other" ->
                        D.succeed Other

                    somethingElse ->
                        D.fail <| "Invalid infoCategory: " ++ somethingElse
            )


responseTypeDecoder : D.Decoder AlertInfoResponseType
responseTypeDecoder =
    D.string
        |> D.andThen
            (\str ->
                case str of
                    "Shelter" ->
                        D.succeed Shelter

                    "Evacuate" ->
                        D.succeed Evacuate

                    "Prepare" ->
                        D.succeed Prepare

                    "Execute" ->
                        D.succeed Execute

                    "Avoid" ->
                        D.succeed Avoid

                    "Monitor" ->
                        D.succeed Monitor

                    "Assess" ->
                        D.succeed Assess

                    "AllClear" ->
                        D.succeed AllClear

                    "None" ->
                        D.succeed None

                    somethingElse ->
                        D.fail <| "Invalid responseType: " ++ somethingElse
            )


urgencyDecoder : D.Decoder AlertInfoUrgency
urgencyDecoder =
    D.string
        |> D.andThen
            (\str ->
                case str of
                    "Immediate" ->
                        D.succeed Immediate

                    "Expected" ->
                        D.succeed Expected

                    "Future" ->
                        D.succeed Future

                    "Past" ->
                        D.succeed Past

                    "Unknown" ->
                        D.succeed Unknown

                    somethingElse ->
                        D.fail <| "Invalid urgency: " ++ somethingElse
            )


certaintyDecoder : D.Decoder AlertInfoCertainty
certaintyDecoder =
    D.string
        |> D.andThen
            (\str ->
                case str of
                    "Observed" ->
                        D.succeed Observed

                    "Likely" ->
                        D.succeed Likely

                    "Very Likely" ->
                        D.succeed Likely

                    "VeryLikely" ->
                        D.succeed Likely

                    "Very likely" ->
                        D.succeed Likely

                    "Possible" ->
                        D.succeed Possible

                    "Unlikely" ->
                        D.succeed Unlikely

                    "UnknownCertainty" ->
                        D.succeed UnknownCertainty

                    somethingElse ->
                        D.fail <| "Invalid certainty: " ++ somethingElse
            )


severityDecoder : D.Decoder AlertInfoSeverity
severityDecoder =
    D.string
        |> D.andThen
            (\str ->
                case str of
                    "Extreme" ->
                        D.succeed Extreme

                    "Severe" ->
                        D.succeed Severe

                    "Moderate" ->
                        D.succeed Moderate

                    "Minor" ->
                        D.succeed Minor

                    "UnknownSeverity" ->
                        D.succeed UnknownSeverity

                    somethingElse ->
                        D.fail <| "Invalid severity: " ++ somethingElse
            )


oStringDecoder : D.Decoder (Maybe String)
oStringDecoder =
    D.nullable D.string


alertResourceDecoder : D.Decoder AlertResource
alertResourceDecoder =
    D.succeed AlertResource
        |> required "resourceDescription" D.string
        |> required "mimeType" D.string
        |> required "size" (D.nullable D.int)
        |> required "uri" oStringDecoder
        |> required "derefUri" oStringDecoder
        |> required "digest" oStringDecoder


alertInfoDecoder : D.Decoder AlertInfo
alertInfoDecoder =
    D.succeed AlertInfo
        |> required "language" D.string
        |> required "category" infoCategoryDecoder
        |> required "event" D.string
        |> required "responseType" (D.nullable responseTypeDecoder)
        |> required "urgency" urgencyDecoder
        |> required "severity" severityDecoder
        |> required "certainty" certaintyDecoder
        |> required "audience" oStringDecoder
        |> required "eventCodes" (D.dict D.string)
        |> required "effective" oStringDecoder
        |> required "onset" oStringDecoder
        |> required "expires" oStringDecoder
        |> required "senderName" oStringDecoder
        |> required "headline" oStringDecoder
        |> required "description" oStringDecoder
        |> required "instruction" oStringDecoder
        |> required "web" oStringDecoder
        |> required "contact" oStringDecoder
        |> required "parameters" (D.dict D.string)
        |> required "resources" (D.list alertResourceDecoder)
        |> hardcoded [] -- TODO: fix


alertDecoder : D.Decoder Alert
alertDecoder =
    D.succeed Alert
        |> required "rawXml" D.string
        |> requiredAt [ "alert", "id" ] D.string
        |> requiredAt [ "alert", "sender" ] D.string
        |> requiredAt [ "alert", "sent" ] D.string
        |> requiredAt [ "alert", "status" ] statusDecoder
        |> requiredAt [ "alert", "msgType" ] typeDecoder
        |> requiredAt [ "alert", "source" ] oStringDecoder
        |> requiredAt [ "alert", "scope" ] scopeDecoder
        |> requiredAt [ "alert", "code" ] (D.list D.string)
        |> requiredAt [ "alert", "references" ] oStringDecoder
        |> requiredAt [ "alert", "addresses" ] oStringDecoder
        |> requiredAt [ "alert", "restriction" ] oStringDecoder
        |> requiredAt [ "alert", "note" ] oStringDecoder
        |> requiredAt [ "alert", "incidents" ] oStringDecoder
        |> requiredAt [ "alert", "infos" ] (D.list alertInfoDecoder)
        |> hardcoded [] -- TODO: fix


alertListDecoder : D.Decoder (List Alert)
alertListDecoder =
    D.list alertDecoder


init : FlagData -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init flags url key =
    ( { alerts = []
      , connectionStatus = Connecting
      , lastUpdate = 0
      , key = key
      , url = url
      , search = ""
      , language = flags.language
      }
    , Cmd.none
    )


type Msg
    = LinkClicked Browser.UrlRequest
    | UrlChanged Url.Url
    | SearchChange String
    | UpdateAlerts D.Value
    | UpdateConnectionStatus String


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

        UpdateAlerts newAlerts ->
            ( { model
                | alerts =
                    List.concat
                        [ model.alerts

                        --, case log "decodeVal" (D.decodeValue alertListDecoder newAlerts) of
                        , case D.decodeValue alertListDecoder newAlerts of
                            Ok x ->
                                List.map (\a -> SomeAlert a) x

                            Err err ->
                                -- this is a hack to log the error then
                                Tuple.first ([], log "decoding error" err)
                        ]
              }
            , Cmd.none
            )

        UpdateConnectionStatus newStatus ->
            ( { model | connectionStatus = case newStatus of
                    "Connected" -> Connected
                    "Connecting" -> Connecting
                    "Disconnected" -> Disconnected
                    _ -> Disconnected -- hack, so I don't need error handling here
                }
            , Cmd.none
            )



-- VIEW


websiteName : String
websiteName =
    "alerts.test"


viewLink : String -> String -> Html msg
viewLink name path =
    a [ href path, class "header-link" ] [ text name ]


headerEle : ConnectionStatus -> Int -> Html Msg
headerEle status lastUpdate =
    header []
        [ h1 [ id "header-title" ]
            [ viewLink websiteName "/"
            ]
        , viewLink "FAQ" "/faq"
        , viewLink "About" "/about"
        , connectionStatusEle status
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


genAlertHtml : AlertOrError -> Html Msg
genAlertHtml maybeAlert =
    case maybeAlert of
        SomeAlert alert ->
            div [ class "alert" ] [ text alert.id ]

        InvalidAlert err ->
            div [ class "alert" ] [ text <| "error parsing alert: " ++ err ]


connectionStatusEle : ConnectionStatus -> Html Msg
connectionStatusEle status =
    div [ class "connection-status" ]
        [ text
            (case status of
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
            [ lazy2 headerEle model.connectionStatus model.lastUpdate
            , div [ id "content" ]
                (case Parser.parse route model.url of
                    Just About ->
                        [ subheader "About" ]

                    Just Faq ->
                        [ subheader "FAQ" ]

                    Just (Search _) ->
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
