;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; A Simple Fluid Dynamics Example:
;;
;; A nice and simple 2d fluid simulation
;; based on code from Jos Stam and Mike Ash.
;;
;; This little example is nice and simple
;; The computation is all on the CPU and
;; the density of each cell is drawn using
;; very simple immediate OpenGL calls.
;;
;; The simulation is a little smoke sim
;; with constant air streams from bottom->top
;; and from left->right.  Smoke is injected
;; into the system semi-regularly.
;; 
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; start new procs
(ipc:new "fluid" 7094)

;; optimize compiles
(llvm:optimize #t)


;; (definec range-limit
;;   (lambda (v:double l:double h:double)
;;     (if (< v l) l
;; 	(if (> v h) h
;; 	    v))))

;(load "../libs/dsp_library.scm")
(load "libs/opengl_lib.scm")


(definec range-limit
  (lambda (h:double l:double v:double)
    (if (< v l) l
	(if (> v h) h
	    v))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; First the fluid dynamics code
;;
;; code here largely pilfered from from
;; Jos Stam and Mike Ash
;;

(bind-type fluidcube <i64,double,double,double,double*,double*,double*,double*,double*,double*,i64>)

(definec fluid-ix
  (lambda (x:i64 y:i64 N:i64)
    (+ x (* y N))))


(definec fluid-cube-create
  (lambda (size-x size-y diffusion viscosity dt:double)
    (let ((cube (heap-alloc fluidcube))
	  (size2:i64 (* size-x size-y 10))
	  (s (heap-alloc size2 double))
	  (density (heap-alloc size2 double))
	  (Vx (heap-alloc size2 double))
	  (Vy (heap-alloc size2 double))
	  (Vx0 (heap-alloc size2 double))
	  (Vy0 (heap-alloc size2 double)))
      (tfill! cube size-x dt diffusion viscosity s density Vx Vy Vx0 Vy0 size-y)
      cube)))


(definec fluid-cube-add-density
  (lambda (cube:fluidcube* x y amount:double)
    (let ((N (tref cube 0))
	  (idx (+ x (* y N)))
	  (density-ptr:double* (tref cube 5))
	  (density (pref density-ptr idx)))
      ;(printf "idx: %d:%d:%d:%d\n" idx N x y)
      (pset! density-ptr idx (+ density amount))
      (+ density amount))))


(definec fluid-cube-add-velocity
  (lambda (cube:fluidcube* x y amount-x:double amount-y:double)
    (let ((N (tref cube 0))
	  (idx (+ x (* y N)))
	  (_Vx (tref cube 6))
	  (_Vy (tref cube 7)))
      (pset! _Vx idx (+ amount-x (pref _Vx idx)))
      (pset! _Vy idx (+ amount-y (pref _Vy idx)))
      cube)))


;; I don't want boundary conditions for this one
(definec fluid-set-boundary
  (lambda (b:i64 x:double* Ny:i64 N:i64)
      1))


(definec fluid-lin-solve
  (lambda (b:i64 x:double* x0:double* a c iter:i64 Ny:i64 N:i64)
    (let ((cRecip (/ 1.0 c))
	  (k 0)
	  (m 0)
	  (j 0)
	  (i 0))
      (dotimes (k iter)
	(dotimes (j (- Ny 1))
	  (dotimes (i (- N 1))
	    (pset! x (+ (+ i 1) (* (+ j 1) N))
		   (* cRecip
		      (+ (pref x0 (+ (+ i 1) (* (+ j 1) N)))
			 (* a (+ (pref x (+ (+ i 2) (* (+ j 1) N)))
				 (pref x (+ i (* (+ j 1) N)))
				 (pref x (+ (+ i 1) (* (+ j 2) N)))
				 (pref x (+ (+ i 1) (* j N)))))))))))
      (fluid-set-boundary b x Ny N))
    1))


(definec fluid-diffuse
  (lambda (b:i64 x:double* x0:double* diff:double dt:double iter Ny N)
    (let ((a:double (* dt diff (i64tod (- N 2)))))
      (fluid-lin-solve b x x0 a (+ 1.0 (* 6.0 a)) iter Ny N))))


(definec fluid-project
  (lambda (velocx:double* velocy:double* p:double* div:double* iter Ny N)
    (let ((j 0)
	  (i 0)
	  (jj 0)
	  (ii 0))
      (dotimes (j (- Ny 1))
	(dotimes (i (- N 1))
	  (pset! div (+ (+ i 1) (* (+ j 1) N))
		 (* -0.5 (/ (+ (- (pref velocx (+ (+ i 2) (* (+ j 1) N)))
				  (pref velocx (+ i (* (+ j 1) N))))
			       (- (pref velocy (+ (+ i 1) (* (+ j 2) N)))
				  (pref velocy (+ (+ i 1) (* j N)))))
			    (i64tod N))))
	  (pset! p (+ (+ i 1) (* (+ j 1) N)) 0.0)
	  1))
    
      (fluid-set-boundary 0 div Ny N)
      (fluid-set-boundary 0 p Ny N)
      (fluid-lin-solve 0 p div 1.0 6.0 iter Ny N)

      (dotimes (jj (- Ny 1))
	(dotimes (ii (- N 1))
	  (pset! velocx (+ (+ ii 1) (* (+ jj 1) N))
		 (- (pref velocx (+ (+ ii 1) (* (+ jj 1) N)))
		    (* 0.5
		       (- (pref p (+ (+ ii 2) (* (+ jj 1) N)))
			  (pref p (+ (+ ii 0) (* (+ jj 1) N))))
		       (i64tod N))))
	  (pset! velocy (+ (+ ii 1) (* (+ jj 1) N))
		 (- (pref velocy (+ (+ ii 1) (* (+ jj 1) N)))
		    (* 0.5
		       (- (pref p (+ (+ ii 1) (* (+ jj 2) N)))
			  (pref p (+ (+ ii 1) (* (+ jj 0) N))))
		       (i64tod N))))
	  1))

    (fluid-set-boundary 1 velocx Ny N)
    (fluid-set-boundary 2 velocy Ny N)
    
    1)))


(definec fluid-advect
  (lambda (b:i64 d:double* d0:double* velocx:double* velocy:double* dt:double Ny:i64 N:i64)
    (let ((n-1 (i64tod (- N 1)))
	  (dtx (* dt n-1))
	  (dty (* dt n-1))
	  (jfloat 0.0) (ifloat 0.0)
	  (s0 0.0) (s1 0.0) (t0 0.0) (t1 0.0)
	  (i0 0.0) (i0i 0) (i1 0.0) (i1i 0)
	  (j0 0.0) (j0i 0) (j1 0.0) (j1i 0)
	  (j:i64 0) (i:i64 0)
	  (tmp1 0.0) (tmp2 0.0) (tmp3 0.0)
	  (x 0.0) (y 0.0) (z 0.0)
	  (Nfloat (i64tod N)))
      (dotimes (j (- Ny 1))
	(set! jfloat (+ jfloat 1.0))
	(set! ifloat 0.0)
	(dotimes (i (- N 1))
	  (set! ifloat (+ ifloat 1.0))
	  (set! tmp1 (* dtx (pref velocx (+ (+ i 1) (* (+ j 1) N)))))
	  (set! tmp2 (* dty (pref velocy (+ (+ i 1) (* (+ j 1) N)))))
	  (set! x (- ifloat tmp1))
	  (set! y (- jfloat tmp2))
	  
	  (if (< x 0.5) (set! x 0.5))
	  (if (> x (+ Nfloat 0.5)) (set! x (+ Nfloat 0.5)))
	  (set! i0 (floor x))
	  (set! i1 (+ i0 1.0))
	  (if (< y 0.5) (set! y 0.5))
	  (if (> y (+ Nfloat 0.5)) (set! y (+ Nfloat 0.5)))
	  (set! j0 (floor y))
	  (set! j1 (+ j0 1.0))

	  (set! s1 (- x i0))
	  (set! s0 (- 1.0 s1))
	  (set! t1 (- y j0))
	  (set! t0 (- 1.0 t1))

	  (set! i0i (dtoi64 i0))
	  (set! i1i (dtoi64 i1))	      
	  (set! j0i (dtoi64 j0))
	  (set! j1i (dtoi64 j1))

	  (pset! d (+ (+ i 1) (* (+ j 1) N))
		 (+ (* s0 (+ (* t0 (pref d0 (+ i0i (* j0i N))))
			     (* t1 (pref d0 (+ i0i (* j1i N))))))
		    (* s1 (+ (* t0 (pref d0 (+ i1i (* j0i N))))
			     (* t1 (pref d0 (+ i1i (* j1i N))))))))))
	  
      (fluid-set-boundary b d Ny N))))

				 
				       
(definec fluid-step-cube
  (lambda (cube:fluidcube*)
    (let ((N (tref cube 0))
	  (Ny (tref cube 10))
	  (dt (tref cube 1))	  
	  (diff (tref cube 2))
	  (visc (tref cube 3))	  
	  (s (tref cube 4))
	  (k 0)
	  (iter 7)
	  (kk 0)
	  (density (tref cube 5))
	  (Vx (tref cube 6))
	  (Vy (tref cube 7))
	  (Vx0 (tref cube 8))
	  (Vy0 (tref cube 9))
	  (time (now)))
      (fluid-diffuse 1 Vx0 Vx visc dt iter Ny N)
      (fluid-diffuse 2 Vy0 Vy visc dt iter Ny N)
      
      ;; (dotimes (k (* Ny N))
      ;; 	(pset! Vx k 0.0)
      ;; 	(pset! Vy k 0.0))

      (fluid-project Vx0 Vy0 Vx Vy iter Ny N)

      (fluid-advect 1 Vx Vx0 Vx0 Vy0 dt Ny N)
      (fluid-advect 2 Vy Vy0 Vx0 Vy0 dt Ny N)

      ;; (dotimes (kk (* Ny N))
      ;; 	(pset! Vx0 kk 0.0)
      ;; 	(pset! Vy0 kk 0.0))      
            
      (fluid-project Vx Vy Vx0 Vy0 iter Ny N)

      (fluid-diffuse 0 s density diff dt iter Ny N)
      (fluid-advect 0 density s Vx Vy dt Ny N)      

      ;(printf "time: %lld:%lld\n" (now) (- (now) time))
      cube)))


(definec get-fluid-cube
;   (let ((cube (fluid-cube-create 322 182 0.0002 0.00002 0.05)))    ; test
   (let ((cube (fluid-cube-create 322 182 0.0002 0.00002 0.05)))    ; test               
    (lambda ()
      cube)))

(definec fluid-fsc
  (lambda ()
    (fluid-step-cube (get-fluid-cube))))



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Data Handling
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(bind-val osc_xs double* (sys:make-cptr (* 20 8)))
(bind-val osc_ys double* (sys:make-cptr (* 20 8)))
(bind-val osc_xxs double* (sys:make-cptr (* 20 8)))
(bind-val osc_yys double* (sys:make-cptr (* 20 8)))
(bind-val osc_vols double* (sys:make-cptr (* 20 8)))
(bind-val osc_grads double* (sys:make-cptr (* 20 8)))
(bind-val osc_alive i64* (sys:make-cptr (* 20 8)))
(bind-val vehicles_x double* (sys:make-cptr (* 1000 8)))
(bind-val vehicles_y double* (sys:make-cptr (* 1000 8)))
(bind-val vehicles_xx double* (sys:make-cptr (* 1000 8)))
(bind-val vehicles_yy double* (sys:make-cptr (* 1000 8)))
(bind-val ubo i32 -1)
(bind-val vehicles float* (sys:make-cptr (* 2000 4)))

(definec init-osc-vars
  (lambda ()
    (let ((i 0))
      (dotimes (i 20)
	(pset! osc_xs i 100.0)
	(pset! osc_ys i 100.0)
	(pset! osc_xxs i 0.0)
	(pset! osc_yys i 0.0)
	(pset! osc_yys i 0.0)
	(pset! osc_vols i 0.0)
	(pset! osc_grads i 0.0)
	(pset! osc_alive i 0)))))

(init-osc-vars)




;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; OPENGL DRAWING STUFF!
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;
 
(definec add-density
  (lambda (x:i64 y:i64 amount:double)
    (let ((cube (get-fluid-cube)))
      (fluid-cube-add-density cube x y amount))))

(definec add-velocity
  (lambda (x y amount-x amount-y)
    (fluid-cube-add-velocity (get-fluid-cube) x y amount-x amount-y)))

(definec get-velocity
  (lambda (x y)
    (let ((xs (tref (get-fluid-cube) 6))
	  (size (tref (get-fluid-cube) 0)))
      (pref xs (+ x (* y size))))))


(definec note-active
  (lambda (idx)
    (pref osc_alive idx)))

(definec note-pitch
  (lambda (idx)
    (pref osc_xs idx)))

(definec note-activity
  (lambda (idx)
    (+ (pref osc_xxs idx)
       (pref osc_yys idx))))

(definec note-grad
  (lambda (idx)
    (pref osc_grads idx)))


(definec update-fluid-sym-state
  (lambda ()
    (let ((i 0))
      (dotimes (i 20)
	(if (> (note-active i) 0)
	    (let ((x (dtoi64 (range-limit (* 322.0 (- (* 1.1 (pref osc_xs i)) .05)) 1.0 321.0)))
		  (ya (pref osc_ys i))
		  (y (dtoi64 (+ 1.0 (* 181.0 ya))))
		  (xx (pref osc_xxs i))
		  (yy (pref osc_yys i)))
	      (add-velocity x y (* 1000.0 xx) (* -1000.0 yy))
	      1)			    
	    1))
      1)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; helpers for opengl rendering of fluidsym
(definec set-data-arrays-lines
  (lambda (cube:fluidcube* point_data:float* color_data:float* offset:float n:i64)
    (let ((ii:i64 0)
	  (jj:i64 0)    
	  (Vx (tref cube 6))
	  (Vy (tref cube 7))
	  (size (tref cube 0))
	  (size-y (tref cube 10))
	  (cnt 0)
	  (red (dtof 0.3))
	  (blue (dtof 0.9))
	  (green (dtof 0.0))
	  (trans (dtof 0.9))
	  (mn:double 0.0))
      (dotimes (jj (- size-y 2))
	(dotimes (ii (- size 2))
	  (let ((idx (+ (+ ii 1) (* (+ jj 1) size)))
		(xv (pref Vx idx))
		(yv (pref Vy idx))		
		(norm (* 1.0 (sqrt (+ (* xv xv) (* yv yv)))))
		(n1 1.0)) ;(fabs (/ norm 0.5))))
	    ;(set! norm (* 0.125 norm))
	    ;(set! norm (* 0.0 norm))	    
	    (if (> norm mn) (set! mn norm))
	    (pset! point_data (+ 0 (* 4 cnt)) (i64tof ii))
	    (pset! point_data (+ 1 (* 4 cnt)) (+ offset (i64tof jj)))
	    (pset! point_data (+ 2 (* 4 cnt)) (dtof (+ (/ xv norm)
							(i64tod ii))))
	    (pset! point_data (+ 3 (* 4 cnt)) (dtof (+ (ftod offset)
						       (i64tod jj)
						       (/ yv norm))))
	    (pset! color_data (+ 0 (* 8 cnt)) red)
	    (pset! color_data (+ 1 (* 8 cnt)) green)
	    (pset! color_data (+ 2 (* 8 cnt)) blue)
	    (pset! color_data (+ 3 (* 8 cnt)) 1.0) ;(dtof (* 4.0 n1))) ;(dtof n1)) ;(dtof (/ norm 10.0))) ;trans) ;trans)
	    (pset! color_data (+ 4 (* 8 cnt)) red)
	    (pset! color_data (+ 5 (* 8 cnt)) green)
	    (pset! color_data (+ 6 (* 8 cnt)) blue)
	    (pset! color_data (+ 7 (* 8 cnt)) (dtof (* 4.0 n1))) ; (dtof (/ norm 10.0)))
	    (set! cnt (+ cnt 1))))))
    void))


(definec set-data-arrays-points
  (lambda (cube:fluidcube* point_data:float* color_data:float* offset:float n:i64)
    (let ((densities (tref cube 5))
	  (ii:i64 0)
	  (jj:i64 0)	    
	  (Vx (tref cube 6))
	  (Vy (tref cube 7))
	  (size (tref cube 0))
	  (size-y (tref cube 10))
	  (cvar:float 0.0)
	  (cnt 0)
	  (red (dtof 1.0)) ;(dtof 0.3))
	  (blue (dtof 0.1))
	  (green (dtof 0.2))) ;(dtof .2)))
      (dotimes (ii (- size 2))
	(dotimes (jj (- size-y 2))
	  (let ((idx (+ (+ ii 1) (* (+ jj 1) size))))
	    (pset! point_data (+ 0 (* 2 cnt)) (i64tof ii))
	    (pset! point_data (+ 1 (* 2 cnt)) (+ offset (i64tof jj)))
	    (set! cvar (dtof (* 1.0 (pref densities idx))))
	    (pset! color_data (+ 0 (* 4 cnt)) (* cvar red))
	    (pset! color_data (+ 1 (* 4 cnt)) (* cvar green))
	    (pset! color_data (+ 2 (* 4 cnt)) (* cvar blue)) ;(* cvar (- 1.0 blue)))	    
	    (pset! color_data (+ 3 (* 4 cnt)) 1.0)
	    (set! cnt (+ cnt 1))))))
    void))



  ;; a trivial opengl draw loop
;; need to call glfwSwapBuffers to flush
(definec gl-loop
  (let ((degree 0.0)
	(point_data1 (halloc 10000000 float))
	(color_data1 (halloc 10000000 float))
	(point_data2 (halloc 10000000 float))
	(color_data2 (halloc 10000000 float)))
    (lambda ()      
      (update-fluid-sym-state)
      (glEnable GL_BLEND)
      (glBlendFunc GL_SRC_ALPHA (+ GL_SRC_ALPHA 1))
      (glDisable GL_DEPTH_TEST)
      
      (glClearColor 0.0 0.0 0.0 1.0)
      (glClear (+ GL_COLOR_BUFFER_BIT GL_DEPTH_BUFFER_BIT))
      (glColorMaterial GL_FRONT_AND_BACK GL_AMBIENT_AND_DIFFUSE)

      (glEnable GL_COLOR_MATERIAL)
      (glColor4d 0.0 0.0 0.0 1.0)
      (glLoadIdentity)
      (glEnable GL_LINE_SMOOTH)
      (glEnable GL_POINT_SMOOTH)      
      (glPointSize 10.0)
      ;(glTranslated -160.0 -178.0 (* 2.0 -370.0))
      (glTranslated -160.0 -89.0 (* 1.0 -370.0))      
      ;(glTranslated -160.0 -180.0 -200.0)
            
      (glEnableClientState GL_VERTEX_ARRAY)
      (glEnableClientState GL_COLOR_ARRAY)

      (set-data-arrays-points (get-fluid-cube) point_data1 color_data1 0.0 1)     
      (glVertexPointer 2 GL_FLOAT 0 (bitcast point_data1 i8*))
      (glColorPointer 4 GL_FLOAT 0 (bitcast color_data1 i8*))	
      (glDrawArrays GL_POINTS 0 (i64toi32 (/ (* 320 180) 1))) ; size-y)))      
      
      ;; (set-data-arrays-lines (get-fluid-cube) point_data2 color_data2 0.0 1)
      ;; (glVertexPointer 2 GL_FLOAT 0 (bitcast point_data2 i8*))
      ;; (glColorPointer 4 GL_FLOAT 0 (bitcast color_data2 i8*))	
      ;; (glDrawArrays GL_LINES 0 (i64toi32 (/ (* 320 180 2) 1))) ; size-y)))

      
      (glDisableClientState GL_VERTEX_ARRAY)
      (glDisableClientState GL_COLOR_ARRAY)

      1)))


(definec burners
  (lambda (time:double)
    (let ((i 0))      
      (dotimes (i 1)
      	(add-density 250 130 50.0)
      	(add-velocity 250 130 (* 10.0 (cos (* time .00001))) (* 10.0 (cos (* time .0001))))
      	(add-density 2 80 100.0)	
      	(add-velocity 2 80 10.0 0.0)
	(add-density 150 2 200.0)
      	(add-velocity 150 2 0.0 (* 50.0 (cos (* time 0.00005))))))
    void))


;;
;; opengl-test includes two sources
;; of constant wind speed
;;
;; bottom->top: straight up the middle
;; left->right: oscillates from back to front
;;
;; You might need to slow the rate of this
;; temporal recursion down if your machine
;; doesn't cope.  (i.e. 3000 to 5000 or more
;;
;; standard impromptu callback
(define opengl-test
  (lambda (time degree)
    (if (< (+ time 0) (now))
    	(println 'gl-behind (- time (now))))

    (burners time)
    (gl-loop)
    (gl:swap-buffers pr2)    

    (ipc:call-async "fluid" 'fluid-fsc)
    
    ;(fluid-step-cube (get-fluid-cube))
    (callback (+ time 0) 'opengl-test
	      (if (< time (now))
		  (+ time 5000)
		  (+ time 1800))
	      (+ degree 0.001))))



;(define pr2 (gl:make-ctx ":0.0" #f 0.0 0.0 1000.0 1000.0))
(define pr2 (gl:make-ctx ":0.0" #f 0.0 0.0 900.0 600.0))
(gl-set-view 900.0 600.0)


(begin (ipc:definec "fluid" 'fluid-fsc)
       (sys:sleep 44100)
       (opengl-test (now) 0.0)
       (add-density 50 50 1000.0)
       (add-velocity 50 50 1000.0 1000.0))


(definec set-dat
  (lambda (x:double y:double)
    (if (> x 0.0)
	(begin (pset! osc_alive 0 1)
	       (pset! osc_xs 0 x)
	       (pset! osc_ys 0 y)
	       (pset! osc_xxs 0 .05)
	       (pset! osc_yys 0 .05)
	       1)
	(begin (pset! osc_alive 0 0)
	       1))))


(define evt-loop
  (let ((px 0.0)
	(py 0.0))
    (lambda ()
      (let ((evt (gl:get-event)))
	(if (not (null? evt))
	    (let ((x (real->integer (/ (cadr evt) 2.803)))
		  (y (real->integer (/ (- 600.0 (car evt)) 3.314))))
	      (set-dat (range-limit (/ x 320.0) 2. 320.0)
		       (range-limit (/ y 180.0) 2. 180.0))
	      ;(add-density x y 20.0)
	      1)
	    (begin (set-dat -1.0 0.0)
	      1)))
      (callback (+ (now) 1000) 'evt-loop))))

(evt-loop)