port module Main exposing (updateAlerts, updateConnectionStatus)

import Browser
import Browser.Navigation as Nav
import DateFormat
import DateFormat.Relative exposing (relativeTime)
import Debug exposing (log)
import Dict exposing (Dict)
import Html exposing (..)
import Html.Attributes exposing (class, href, id)
import Html.Events exposing (onClick)
import Html.Lazy exposing (lazy2)
import Json.Decode as D
import Json.Decode.Pipeline exposing (hardcoded, required, requiredAt)
import List
import Task
import Time
import Url
import Url.Parser as Parser exposing ((</>), Parser, map, oneOf, s, top)



-- MAIN


port updateAlerts : (D.Value -> msg) -> Sub msg


port updateConnectionStatus : (String -> msg) -> Sub msg


port updateMapData : (List (String, List String) -> msg) -> Sub msg


port updateMapPolygons : (List (String, List
    { areaDesc : String
    , polygon : Maybe String
    , circle : Maybe String
    , altitude : Maybe Int
    , ceiling : Maybe Int
    })) -> Cmd msg


type alias FlagData =
    { language : String
    , now : Int
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
        , Time.every 30000 Tick
        ]



-- MODEL


type MsgType
    = Alert_
    | Update
    | Cancel
    | Ack
    | Error


stringifyMsgType : MsgType -> String
stringifyMsgType x =
    case x of
        Alert_ ->
            "Alert"

        Update ->
            "Update"

        Cancel ->
            "Cancel"

        Ack ->
            "Acknowledgement"

        Error ->
            "Error"


type MsgStatus
    = Actual
    | Exercise
    | System
    | Test
    | Draft


stringifyMsgStatus : MsgStatus -> String
stringifyMsgStatus x =
    case x of
        Actual ->
            "Actual"

        Exercise ->
            "Exercise"

        System ->
            "System"

        Test ->
            "Test"

        Draft ->
            "Draft"


type MsgScope
    = Public
      -- really, we should only see Public alerts since all alerts are public in Canada
    | Restricted
    | Private


stringifyMsgScope : MsgScope -> String
stringifyMsgScope x =
    case x of
        Public ->
            "Public"

        Restricted ->
            "Restricted"

        Private ->
            "Private"


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
    , altitude : Maybe Int
    , ceiling : Maybe Int
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


stringifyAlertInfoCategory : AlertInfoCategory -> String
stringifyAlertInfoCategory x =
    case x of
        Geo ->
            "Geographic"

        Met ->
            "Meterological"

        Safety ->
            "Safety"

        Security ->
            "Security"

        Rescue ->
            "Rescue"

        Fire ->
            "Fire"

        Health ->
            "Health"

        Env ->
            "Enviroment"

        Transport ->
            "Transport"

        Infra ->
            "Infrastructure"

        CBRNE ->
            "CBRNE (Chemical, Biological, Radiological, Nuclear, and Explosive materials)"

        Other ->
            "Other"


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


stringifyAlertInfoResponseType : AlertInfoResponseType -> String
stringifyAlertInfoResponseType x =
    case x of
        Shelter ->
            "Shelter"

        Evacuate ->
            "Evacuate"

        Prepare ->
            "Prepare"

        Execute ->
            "Execute"

        Avoid ->
            "Avoid"

        Monitor ->
            "Monitor"

        Assess ->
            "Assess"

        AllClear ->
            "All clear"

        None ->
            ""


type AlertInfoUrgency
    = Immediate
    | Expected
    | Future
    | Past
    | Unknown


stringifyAlertInfoUrgency : AlertInfoUrgency -> String
stringifyAlertInfoUrgency x =
    case x of
        Immediate ->
            "Immediate"

        Expected ->
            "Expected"

        Future ->
            "Future"

        Past ->
            "Past"

        Unknown ->
            ""


type AlertInfoSeverity
    = Extreme
    | Severe
    | Moderate
    | Minor
    | UnknownSeverity


stringifyAlertInfoSeverity : AlertInfoSeverity -> String
stringifyAlertInfoSeverity x =
    case x of
        Extreme ->
            "Extreme"

        Severe ->
            "Severe"

        Moderate ->
            "Moderate"

        Minor ->
            "Minor"

        UnknownSeverity ->
            ""


type AlertInfoCertainty
    = Observed
      -- For backward compatibility with CAP 1.0, the deprecated value of “Very Likely” SHOULD be
      -- treated as equivalent to “Likely” -- spec
    | Likely
    | Possible
    | Unlikely
    | UnknownCertainty


stringifyAlertInfoCertainty : AlertInfoCertainty -> String
stringifyAlertInfoCertainty x =
    case x of
        Observed ->
            "Observed"

        Likely ->
            "Likely"

        Possible ->
            "Possible"

        Unlikely ->
            "Unlikely"

        UnknownCertainty ->
            ""


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
    , effective : Maybe Int
    , onset : Maybe Int
    , expires : Maybe Int
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
    , sent : Int
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
    , timeZone : Time.Zone
    , time : Time.Posix
    , mapEverShown : Bool
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

                    "Unknown" ->
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

                    "Unknown" ->
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


alertAreaDecoder : D.Decoder AlertArea
alertAreaDecoder =
    D.succeed AlertArea
        |> required "areaDesc" D.string
        |> required "polygon" oStringDecoder
        |> required "circle" oStringDecoder
        |> required "geocodes" (D.dict D.string)
        |> required "altitude" (D.nullable D.int)
        |> required "ceiling" (D.nullable D.int)

        

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
        |> required "effective" (D.nullable D.int)
        |> required "onset" (D.nullable D.int)
        |> required "expires" (D.nullable D.int)
        |> required "senderName" oStringDecoder
        |> required "headline" oStringDecoder
        |> required "description" oStringDecoder
        |> required "instruction" oStringDecoder
        |> required "web" oStringDecoder
        |> required "contact" oStringDecoder
        |> required "parameters" (D.dict D.string)
        |> required "resources" (D.list alertResourceDecoder)
        |> required "areas" (D.list alertAreaDecoder)



-- TODO: fix


alertDecoder : D.Decoder Alert
alertDecoder =
    D.succeed Alert
        |> required "rawXml" D.string
        |> requiredAt [ "alert", "id" ] D.string
        |> requiredAt [ "alert", "sender" ] D.string
        |> requiredAt [ "alert", "sent" ] D.int
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
        |> hardcoded []



-- TODO: fix


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
      , timeZone = Time.utc
      , time = Time.millisToPosix flags.now
      , mapEverShown = url.path == "/map"
      }
    , Task.perform TimeZone Time.here
    )


type Msg
    = LinkClicked Browser.UrlRequest
    | UrlChanged Url.Url
    | SearchChange String
    | UpdateAlerts D.Value
    | UpdateConnectionStatus String
    | TimeZone Time.Zone
    | Tick Time.Posix
    | UpdateLanguage String


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
            if url.path == "/map" then
                ({ model | url = url, mapEverShown = True }, Cmd.none)
            else 
                ({ model | url = url }, Cmd.none)

        UpdateAlerts newAlerts ->
            let
                newAlertsList =
                    List.concat
                        [ model.alerts

                        --, case log "decodeVal" (D.decodeValue alertListDecoder newAlerts) of
                        , case D.decodeValue alertListDecoder newAlerts of
                            Ok x ->
                                List.map (\a -> SomeAlert a) x

                            Err err ->
                                -- this is a hack to log the error then
                                Tuple.first ( [], log "decoding error" err )
                        ]
            in
            ( { model | alerts = newAlertsList }
            , updateMapPolygons <| List.filterMap (\x -> case x of
                InvalidAlert _ ->
                    Nothing

                SomeAlert a ->
                    case List.head a.infos of
                        Just h ->
                            Just (a.id, List.map (\area ->
                                { areaDesc = area.areaDesc
                                , polygon = area.polygon
                                , circle = area.circle
                                , altitude = area.altitude
                                , ceiling = area.ceiling
                                }
                            ) h.areas)
                        Nothing ->
                            Nothing
                ) newAlertsList
            )

        UpdateConnectionStatus newStatus ->
            ( { model
                | connectionStatus =
                    case newStatus of
                        "Connected" ->
                            Connected

                        "Connecting" ->
                            Connecting

                        "Disconnected" ->
                            Disconnected

                        _ ->
                            Disconnected

                -- hack, so I don't need error handling here
              }
            , Cmd.none
            )

        TimeZone zone ->
            ( { model | timeZone = zone }
            , Cmd.none
            )

        Tick newTime ->
            ( { model | time = newTime }
            , Cmd.none
            )

        UpdateLanguage lang ->
            ( { model | language = lang }
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
        , viewLink "Map" "/map"
        , viewLink "FAQ" "/faq"
        , viewLink "About" "/about"
        , connectionStatusEle status
        ]


type Route
    = Search String
    | About
    | Faq
    | Map


route : Parser (Route -> a) a
route =
    oneOf
        [ Parser.map (Search "") top
        , Parser.map Search (Parser.s "search" </> Parser.string)
        , Parser.map About (Parser.s "about")
        , Parser.map Faq (Parser.s "faq")
        , Parser.map Search (Parser.s "alert" </> Parser.string)
        , Parser.map Map (Parser.s "map")
        ]


alertInfoForLang : Alert -> String -> Maybe AlertInfo
alertInfoForLang alert lang =
    List.head <| List.filter (\ele -> ele.language == lang) alert.infos


alertTitle : AlertInfo -> String
alertTitle info =
    case info.headline of
        Just headline ->
            headline

        Nothing ->
            "(untitled alert)"


fullDateFormatter : Time.Zone -> Time.Posix -> String
fullDateFormatter =
    DateFormat.format
        [ DateFormat.monthNameFull
        , DateFormat.text " "
        , DateFormat.dayOfMonthSuffix
        , DateFormat.text ", "
        , DateFormat.yearNumber
        , DateFormat.text " "
        , DateFormat.hourNumber
        , DateFormat.text ":"
        , DateFormat.minuteFixed
        , DateFormat.text " "
        , DateFormat.amPmLowercase
        ]


dateEle : Time.Zone -> Int -> Time.Posix -> Html Msg
dateEle zone time now =
    let
        posix =
            Time.millisToPosix time
    in
    span
        [ Html.Attributes.title <| fullDateFormatter zone posix ]
        [ text <| relativeTime now posix
        ]


langToString : String -> String
langToString lang =
    case String.left 2 lang of
        "en" ->
            "English"

        "fr" ->
            "French"

        "iku" ->
            "Inuktitut"

        "iu" ->
            "Inuktitut"

        "ike" ->
            "Inuktitut"

        "ikt" ->
            "Inuinnaqtun"

        other ->
            other


langSelector : List AlertInfo -> Html Msg
langSelector infos =
    div
        [ class "lang-selector" ]
        (infos
            |> List.map (\a -> a.language)
            |> List.map (\a -> div [ class "lang-selector-lang", onClick <| UpdateLanguage a ] [ text <| langToString a ])
        )


alertKeyRaw : Html Msg -> String -> Html Msg
alertKeyRaw content name =
    let
        lowerName =
            String.toLower name

        normalizedName =
            String.replace " " "-" lowerName
    in
        div [ class <| "alert-" ++ normalizedName ] [ span [ class "alert-label" ] [ text <| name ++ ": " ], content ]


alertKey : Maybe String -> String -> Html Msg
alertKey key name =
    case key of
        Nothing -> span [] []
        Just "" -> span [] []
        Just x ->
            alertKeyRaw
                (if String.left 4 x == "http" then
                    a [ href x, Html.Attributes.target "_blank" ] [ text x ]

                else
                    text x)
                name


alertKeyDate : Time.Zone -> Time.Posix -> Maybe Int -> String -> Html Msg
alertKeyDate zone now time name =
    case time of
        Nothing -> span [] []
        Just x ->
            alertKeyRaw (dateEle zone x now) name


alertDiv : Alert -> String -> Time.Zone -> Time.Posix -> Html Msg
alertDiv alert lang zone now =
    let
        date = alertKeyDate zone now
    in
        div [ class "alert" ]
            [ case alertInfoForLang alert lang of
                Just info ->
                    div []
                        [ h3 [ class "alert-title" ] [ text <| alertTitle info ]
                        , langSelector alert.infos
                        , div
                            [ class "alert-sender" ]
                            [ text "Sent "
                            , dateEle zone alert.sent now
                            , text <| " by " ++ alert.sender
                            ]
                        , date info.expires "Expires"
                        , alertKey (Just (stringifyMsgScope alert.scope)) "Scope"
                        , alertKey (Just (stringifyAlertInfoCategory info.category)) "Category"
                        , alertKey (Maybe.map stringifyAlertInfoResponseType info.responseType) "Response type"
                        , alertKey (Just (stringifyAlertInfoCertainty info.certainty)) "Certainty"
                        , alertKey (Just (stringifyAlertInfoSeverity info.severity)) "Severity"
                        , alertKey info.instruction "Instructions"
                        , alertKey info.description "Description"
                        , alertKey info.contact "Contact"
                        , alertKey alert.source "Source"
                        , alertKey info.web "Website"
                        , alertKey info.audience "Audience"
                        , alertKey info.contact "Contact"
                        --, alertKey alert.type (Maybe.map )
                        ]

                Nothing ->
                    div [ class "no-lang-data" ]
                        [ langSelector alert.infos
                        , case List.head alert.infos of
                            Just _ ->
                                text <| "There is no data for this alert in " ++ lang ++ "."

                            Nothing ->
                                text <|
                                    "There is no data for this alert in "
                                        ++ lang
                                        ++ ", or any other language."
                        ]
        ]


subheader : String -> Html Msg
subheader title =
    h2 [ class "subheader" ] [ text title ]


alertFinderWidget : Model -> Html Msg
alertFinderWidget model =
    div [ class "alert-finder-widget" ]
        []


genAlertHtml : String -> Time.Zone -> Time.Posix -> AlertOrError -> Html Msg
genAlertHtml lang zone now maybeAlert =
    case maybeAlert of
        SomeAlert alert ->
            alertDiv alert lang zone now

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
    let
        routedUrl = Parser.parse route model.url
        onMapPage = case routedUrl of
            Just Map ->
                True
            _ ->
                False
    in
        { title = "AlertReady viewer"
        , body =
            [ div [ class "elm-root" ]
                [ lazy2 headerEle model.connectionStatus model.lastUpdate
                , 
                    if model.mapEverShown then
                        node "world-map"
                            [ Html.Attributes.style "display" (if onMapPage then "block" else "none")
                            , id "alert-map"
                            ]
                            []
                    else
                        span [] []

                , div [ id "content" ]
                    (case routedUrl of
                        Just About ->
                            [ subheader "About" ]

                        Just Faq ->
                            [ subheader "FAQ" ]

                        Just Map ->
                            [] -- TODO

                        Just (Search _) ->
                            List.concat
                                [ [ alertFinderWidget model ]
                                , if List.length model.alerts == 0 then
                                    [ div [ class "no-alerts" ] [ text "No alerts found." ] ]

                                else
                                    model.alerts
                                        |> List.sortBy
                                            (\a ->
                                                case a of
                                                    SomeAlert alert ->
                                                        -alert.sent

                                                    InvalidAlert _ ->
                                                        round (1 / 0)
                                            -- hack to get negative infinity
                                            )
                                        |> List.map (genAlertHtml model.language model.timeZone model.time)
                                ]

                        Nothing ->
                            [ subheader "Not found" ]
                    )
                ]
            ]
        }
