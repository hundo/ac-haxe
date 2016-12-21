; Author: Hundo

(require 'auto-complete)
(require 'cl-lib)
(require 'xml)


(defvar ac-haxe--end-of-message "\000")
(defvar ac-haxe--start-of-file "\001")
(defvar ac-haxe--eol "\n")

(defvar ac-haxe--output-buffer-name "*HaxeCompletion*")
(defvar ac-haxe--error-buffer-name "*HaxeCompletionErr*")
(defvar ac-haxe--current-process nil)
(defvar ac-haxe--cached-hxml nil)
(defvar ac-haxe--completion-response nil)

(defvar ac-haxe-exe "haxe")

(defun ac-haxe--project-root ()
  (projectile-project-root))

(defun ac-haxe--msg (&rest args)
  (with-current-buffer ac-haxe--output-buffer-name
    (goto-char (point-max))
    (apply 'insert (list "***AC-HAXE: " (apply 'format args) "§\n"))))

(defun ac-haxe--get-hxml ()
  (let ((buildFile (concat (ac-haxe--project-root) "completion.hxml")))
    (if (file-exists-p buildFile)
        (with-temp-buffer
          (insert-file-contents buildFile)
          (delete-non-matching-lines "^-cp\\|^-lib")
          (setq ac-haxe--cached-hxml
                (mapconcat 'identity
                           (delete-dups
                            (split-string (buffer-string) ac-haxe--eol))
                           ac-haxe--eol)))
      (ac-haxe--msg "Build file does not exist:%s" buildFile))))


(defun ac-haxe--decode-length (str)
  (+ (aref str 0)
     (lsh (aref str 1) 8)
     (lsh (aref str 2) 16)
     (lsh (aref str 3) 24)))

(defun ac-haxe--encode-length (len)
  (let ((str (make-string 4 0)))
    (setf (aref str 0) (logand len #xFF)
          (aref str 1) (logand (lsh len -8) #xFF)
          (aref str 2) (logand (lsh len -16) #xFF)
          (aref str 3) (logand (lsh len -24) #xFF))
    str))

(defun ac-haxe--process-filter (proc raw)
  (ac-haxe--msg "filtering output! %S" proc)
  (when (buffer-live-p (process-buffer proc))
    (with-current-buffer (process-buffer proc)
      (save-excursion
        ;; Insert the text, advancing the process marker.
        (goto-char (process-mark proc))
        (insert raw)
        (set-marker (process-mark proc) (point)))
      (goto-char (process-mark proc))

      (let ((raw (buffer-string)))
        (when (<= 4 (length raw))
          (let ((msg-sz (ac-haxe--decode-length raw)))
            (ac-haxe--msg "message size=%s len=%s msg=%S" msg-sz (length raw) raw)
            (if (> msg-sz 80000)
                (user-error "haxe completion failed, no size header found")
              (condition-case err
                  (when (>= (length raw) (+ msg-sz 4))
                    (ac-haxe--msg "Full MSG. sz=%s" msg-sz)
                    (let ((xmsg (xml-parse-region 5 (+ 4 msg-sz))))
                      (ac-haxe--msg "MSG: %S" xmsg)
                      (if xmsg
                          (setq ac-haxe--completion-response xmsg)
                        (let ((msg (buffer-substring 5 (+ 2 msg-sz))))
                          (ac-haxe--msg "Got msg %s %s!" (length msg) msg)))


                      ))
                (error
                 (ac-haxe--msg "Haxe-completion error: %s"
                               (substring msg 4 (+ 4 msg-sz))))))))))))


(defun ac-haxe--process-response (parsedxml)
  (ac-haxe--msg "Processing: %S" parsedxml)
  (let ((rootnode (car parsedxml)))
    (cl-case (xml-node-name rootnode)
      (list
       (let* ((items (cl-remove-if 'stringp (xml-node-children (car parsedxml))))
              (res (mapcar (lambda (ch)
                             (xml-get-attribute ch 'n))
                           items)))
         (ac-haxe--msg "Procesed: %S" res)
         res))
      (type
       (ac-haxe--msg "Type: %S" (cddr rootnode))
       nil))))


(defun ac-haxe--make-process ()
  (let* ((errpipe (make-pipe-process :name ac-haxe--error-buffer-name
                                     :coding 'binary
                                     ))
         (proc
          (setq ac-haxe--current-process
                (make-process :name ac-haxe--output-buffer-name
                              :buffer ac-haxe--output-buffer-name
                              :stderr errpipe
                              :coding 'binary
                              :connection-type 'pipe
                              :command (list ac-haxe-exe
                                             "-v"
                                             "--wait" "stdio")))))
    

    (with-current-buffer ac-haxe--error-buffer-name
      (set-buffer-multibyte nil))
    (set-process-filter errpipe 'ac-haxe--process-filter)
    ;(set-process-sentinel proc 'company-haxe--process-sentinel)
    (ac-haxe--msg "Haxe Completion process started")
    proc
    ))

(defun ac-haxe--ensure-process ()
  (if (process-live-p ac-haxe--current-process)
      ac-haxe--current-process
    (ac-haxe--make-process)))

(defun ac-haxe--build-command-string ()
  (concat
     "-D display_stdin" ac-haxe--eol
     
     "--cwd " (ac-haxe--project-root) ac-haxe--eol
     
     (ac-haxe--get-hxml) ac-haxe--eol

     "--display " (buffer-file-name) "@" (number-to-string (- ac-point 1)) ac-haxe--eol

     ac-haxe--start-of-file
     (buffer-substring-no-properties 1 (point-max))))


(defun ac-haxe--get-completions ()
  (let ((cmd (ac-haxe--build-command-string))
        (proc (ac-haxe--ensure-process)))
    (ac-haxe--msg "command: %S" cmd)
    (ac-haxe--msg "prefix=%s" ac-prefix)
    (ac-haxe--msg "point=%s" (point))
    (ac-haxe--msg "ac point=%s" ac-point)
    (setq ac-haxe--completion-response nil)

    (with-current-buffer (get-buffer-create ac-haxe--error-buffer-name)
      (erase-buffer))
    
    (process-send-string proc (ac-haxe--encode-length (length cmd)))
    (process-send-string proc cmd)

    (catch 'loop
      (dotimes (i 30)
        (accept-process-output proc 0.3)
        (when ac-haxe--completion-response
          (throw 'loop i))))

    
    (ac-haxe--process-response ac-haxe--completion-response)))


(ac-define-source haxe
  '((candidates . ac-haxe--get-completions)
    (requires . 0)
    (prefix . "[.]\\([^ (]*\\)")))

(defun ac-haxe-setup ()
  (interactive)
  (setq ac-sources '(ac-source-haxe))
  (unless auto-complete-mode
    (auto-complete-mode)))

(provide 'ac-haxe)
