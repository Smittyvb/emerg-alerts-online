module Main exposing (..)

import Browser
import Browser.Navigation as Nav
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick)
import Platform.Cmd exposing (..)
import Url
import Url.Parser as Parser exposing (Parser, oneOf, s, map, top, (</>))


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
    {}


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
    }


init : () -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init flags url key =
    ( { alerts = []
      , connectionStatus = Connected
      , lastUpdate = 0
      , key = key
      , url = url
      }
    , Cmd.none
    )


type Msg
    = LinkClicked Browser.UrlRequest
    | UrlChanged Url.Url


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
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


viewLink : String -> String -> Html msg
viewLink name path =
    a [ href path ] [ text name ]


headerEle : Model -> Html Msg
headerEle model =
    header []
        [ h1 []
            [ text "AlertReady viewer"
            ]
        , viewLink "Home" "/"
        , viewLink "FAQ" "/faq"
        , viewLink "About" "/about"
        ]

type Route
    = Home
    | About
    | Faq
    | SpecificAlert String
    | NotFound

route : Parser (Route -> a) a
route =
  oneOf
    [ Parser.map Home (Parser.s "home")
    , Parser.map About (Parser.s "about")
    , Parser.map Faq (Parser.s "Faq")
    , Parser.map SpecificAlert (Parser.s "alert" </> Parser.string)
    ]

view : Model -> Browser.Document Msg
view model =
    { title = "AlertReady viewer"
    , body =
        [ div []
            [ headerEle model
            
        , div [] [ text (Url.toString model.url) ]
        ]]
    }
