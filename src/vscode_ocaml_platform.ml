open Import

let suggest_to_pick_sandbox instance =
  let open Promise.Syntax in
  let select_pm_button_text = "Select package manager and sandbox" in
  let+ selection =
    Window.showInformationMessage
      ~message:
        "OCaml Platform is using the package manager and sandbox available in \
         the environment. Pick a particular package manager and sandbox by \
         clicking the button below"
      ~choices:[ (select_pm_button_text, ()) ]
      ()
  in
  Option.iter selection ~f:(Extension_commands.select_sandbox.handler instance)

let activate (extension : ExtensionContext.t) =
  (* this env var update disables ocaml-lsp's logging to a file
     because we use vscode [output] pane for logs *)
  Process.Env.set "OCAML_LSP_SERVER_LOG" "-";
  let open Promise.Syntax in
  let* package_manager =
    Toolchain.of_settings ()
    (* TODO: implement [Toolchain.from_settings_or_detect] that would
       either get the sandbox from the settings or detect in a smart way (not simply Global) *)
  in
  let is_fallback = Option.is_empty package_manager in
  let package_manager =
    Option.value package_manager ~default:Toolchain.Package_manager.Global
  in
  Extension_instance.make (Toolchain.make package_manager)
  |> Promise.Result.iter
       ~ok:(fun instance ->
         (* register things with vscode, making sure to register their disposables *)
         let _register_extension_commands : unit =
           Extension_commands.register_all_commands extension instance
         in
         let _register_extension_instance : unit =
           ExtensionContext.subscribe extension
             ~disposable:(Extension_instance.disposable instance)
         in
         let _register_dune_formatter : unit =
           Dune_formatter.register instance
           |> List.iter ~f:(fun disposable ->
                  ExtensionContext.subscribe extension ~disposable)
         in
         let _register_dune_task_provider : unit =
           let disposable = Dune_task_provider.register instance in
           ExtensionContext.subscribe extension ~disposable
         in
         if
           is_fallback
           (* if the toolchain we just set up is a fallback sandbox,
              we create a pop-up message to offer the user to pick a sandbox they want;
              note: if the user picks another sandbox in the pop-up,
                we redo part of work we have just done;
                this is the case because we can't wait or rely on user to pick a sandbox:
                they may ignore the pop-up leaving the extension hanging, so we use fallback;
                w/ a proper detection mechanism, we would redo work in rare cases *)
         then
           let (_ : unit Promise.t) = suggest_to_pick_sandbox instance in
           ())
       ~error:(fun e -> show_message `Error "%s" e)
  |> Promise.catch ~rejected:(fun e ->
         let error_message = Node.JsError.message e in
         show_message `Error "Error: %s" error_message;
         Promise.return ())

let () =
  let open Js_of_ocaml.Js in
  export "activate" (wrap_callback activate)
