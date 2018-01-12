(defun my/ffap ()
  (interactive)
  (let ((filename (ffap-guess-file-name-at-point)))
    (when (not filename)
      (user-error "No file at point"))
    (ffap filename)))


;;; realgud

(defun my/realgud-eval-nth-name-forward (n)
  (interactive "p")
  (save-excursion
    (let (name)
      (while (and (> n 0) (< (point) (point-max)))
        (let ((p (point)))
          (if (not (c-forward-name))
              (progn
                (c-forward-token-2)
                (when (= (point) p) (forward-char 1)))
            (setq name (buffer-substring-no-properties p (point)))
            (cl-decf n 1))))
      (when name
        (realgud:cmd-eval name)
        nil))))

(defun my/realgud-eval-nth-name-backward (n)
  (interactive "p")
  (save-excursion
    (let (name)
      (while (and (> n 0) (> (point) (point-min)))
        (let ((p (point)))
          (c-backward-token-2)
          (when (= (point) p) (backward-char 1))
          (setq p (point))
          (when (c-forward-name)
            (setq name (buffer-substring-no-properties p (point)))
            (goto-char p)
            (cl-decf n 1))))
      (when name
        (realgud:cmd-eval name)
        nil))))

(defun my/realgud-eval-region-or-word-at-point ()
  (interactive)
  (when-let
      ((cmdbuf (realgud-get-cmdbuf))
       (process (get-buffer-process cmdbuf))
       (expr
        (if (evil-visual-state-p)
            (let ((range (evil-visual-range)))
              (buffer-substring-no-properties (evil-range-beginning range)
                                              (evil-range-end range)))
          (word-at-point)
          )))
    (with-current-buffer cmdbuf
	    (setq realgud:process-filter-save (process-filter process))
	    (set-process-filter process 'realgud:eval-process-output))
    (realgud:cmd-eval expr)
    ))


;;; elisp

(defun my/realtime-elisp-doc-function ()
  (let ((w (selected-window)))
    (when-let (s (intern-soft (current-word)))
      (cond
       ((fboundp s) (describe-function s))
       ((boundp s) (describe-variable s))
       )
      (select-window w)
      nil)))

(defun my/realtime-elisp-doc ()
  (interactive)
  (when (eq major-mode 'emacs-lisp-mode)
    (if (advice-function-member-p #'my/realtime-elisp-doc-function eldoc-documentation-function)
        (remove-function (local 'eldoc-documentation-function) #'my/realtime-elisp-doc-function)
      (add-function :after-while (local 'eldoc-documentation-function) #'my/realtime-elisp-doc-function))))


;;; xref

(defun my-xref//references-in-pair ()
  (let ((refs (lsp--send-request (lsp--make-request
                                  "textDocument/references"
                                  (lsp--make-reference-params)))))
    (sort
     (mapcar
      (lambda (ref)
        (let* ((filename (string-remove-prefix lsp--uri-file-prefix (gethash "uri" ref)))
               (range (gethash "range" ref))
               (start (gethash "start" range))
               (line (gethash "line" start))
               (column (gethash "character" start)))
          (list filename line column))) refs)
     (lambda (x y)
       (if (not (string= (car x) (car y)))
           (string< (car x) (car y))
         (if (not (= (cadr x) (cadr y)))
             (< (cadr x) (cadr y))
           (< (caddr x) (caddr y))))))))

(defun my-xref/next-reference ()
  (interactive)
  (let* ((line (lsp--cur-line))
         (column (lsp--cur-column))
         (refs (my-xref//references-in-pair))
         (res (-first (lambda (x)
                        (if (not (string= (car x) buffer-file-name))
                            (string> (car x) buffer-file-name)
                          (if (not (= (cadr x) line))
                              (> (cadr x) line)
                            (> (caddr x) column)))) refs)))
    (when res
      (find-file (car res))
      (goto-char 1)
      (forward-line (cadr res))
      (forward-char (caddr res))
      nil)))

(defun my-xref/previous-reference ()
  (interactive)
  (let* ((line (lsp--cur-line))
         (column (lsp--cur-column))
         (refs (my-xref//references-in-pair))
         (res (-last (lambda (x)
                        (if (not (string= (car x) buffer-file-name))
                            (string< (car x) buffer-file-name)
                          (if (not (= (cadr x) line))
                              (< (cadr x) line)
                            (< (caddr x) column)))) refs)))
    (when res
      (find-file (car res))
      (goto-char 1)
      (forward-line (cadr res))
      (forward-char (caddr res))
      nil)))

;;; Override
;; This function is transitively called by xref-find-{definitions,references,apropos}
(require 'xref)
(defun xref--show-xrefs (xrefs display-action &optional always-show-list)
  (cond
   ((cl-some (lambda (x) (string-match-p x buffer-file-name))
             my-xref-blacklist)
    nil)
   ((and (not (cdr xrefs)) (not always-show-list))
    ;; PATCH
    (lsp-ui-peek--with-evil-jumps (evil-set-jump))

    (xref--pop-to-location (car xrefs) display-action))
   (t
    ;; PATCH
    (lsp-ui-peek--with-evil-jumps (evil-set-jump))

    ;; PATCH Jump to the first candidate
    ;; (when xrefs
      ;; (xref--pop-to-location (car xrefs) display-action))

    (funcall xref-show-xrefs-function xrefs
             `((window . ,(selected-window)))))))


;; https://github.com/syl20bnr/spacemacs/pull/9911

(defmacro spacemacs|define-reference-handlers (mode &rest handlers)
  "Defines reference handlers for the given MODE.
This defines a variable `spacemacs-reference-handlers-MODE' to which
handlers can be added, and a function added to MODE-hook which
sets `spacemacs-reference-handlers' in buffers of that mode."
  (let ((mode-hook (intern (format "%S-hook" mode)))
        (func (intern (format "spacemacs//init-reference-handlers-%S" mode)))
        (handlers-list (intern (format "spacemacs-reference-handlers-%S" mode))))
    `(progn
       (defvar ,handlers-list ',handlers
         ,(format (concat "List of mode-specific reference handlers for %S. "
                          "These take priority over those in "
                          "`spacemacs-default-reference-handlers'.")
                  mode))
       (defun ,func ()
         (setq spacemacs-reference-handlers
               (append ,handlers-list
                       spacemacs-default-reference-handlers)))
       (add-hook ',mode-hook ',func)
       (with-eval-after-load 'bind-map
         (spacemacs/set-leader-keys-for-major-mode ',mode
           "gr" 'spacemacs/jump-to-reference)))))

(defun spacemacs/jump-to-reference ()
  "Jump to reference around point using the best tool for this action."
  (interactive)
  (catch 'done
    (let ((old-window (selected-window))
          (old-buffer (current-buffer))
          (old-point (point)))
      (dolist (-handler spacemacs-reference-handlers)
        (let ((handler (if (listp -handler) (car -handler) -handler))
              (async (when (listp -handler)
                       (plist-get (cdr -handler) :async))))
          (ignore-errors
            (call-interactively handler))
          (when (or (eq async t)
                    (and (fboundp async) (funcall async))
                    (not (eq old-point (point)))
                    (not (equal old-buffer (window-buffer old-window))))
            (throw 'done t)))))
    (message "No reference handler was able to find this symbol.")))

(defun spacemacs/jump-to-reference-other-window ()
  "Jump to reference around point in other window."
  (interactive)
  (let ((pos (point)))
    ;; since `spacemacs/jump-to-reference' can be asynchronous we cannot use
    ;; `save-excursion' here, so we have to bear with the jumpy behavior.
    (switch-to-buffer-other-window (current-buffer))
    (goto-char pos)
    (spacemacs/jump-to-reference)))


;; dumb-jump

(defun my-advice/dumb-jump-go (orig-fun &rest args)
  (unless (or lsp-mode
              (cl-some
               (lambda (x) (string-match-p x buffer-file-name))
               my-xref-blacklist))
    (apply orig-fun args)))