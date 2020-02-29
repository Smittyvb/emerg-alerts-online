module Main exposing (..)

import Browser
import Html exposing (..)
import Html.Events exposing (onClick)

-- MAIN

main =
  Browser.sandbox { init = init, update = update, view = view }

-- MODEL

type alias Alert = {}
type alias Model = { alerts: List Alert, loading: Bool }

init : Model
init =
  { alerts = [], loading: false }

-- UPDATE

type Msg = Noop

update : Msg -> Model -> Model
update msg model =
  case msg of
    Noop ->
      model

-- VIEW

view : Model -> Html Msg
view model =
  div []
    [ h1 [] [ text "AlertReady alerts live" ]
    ]
