; ============================================================================
; 3D Scene.
; ============================================================================

.equ OBJ_MAX_VERTS, 8
.equ OBJ_MAX_FACES, 6
.equ OBJ_MAX_VISIBLE_FACES, 3       ; True for cube.
.equ OBJ_VERTS_PER_FACE, 4
.equ OBJ_MAX_EDGES_PER_FACE, OBJ_VERTS_PER_FACE

.equ object_num_verts, 8
.equ object_num_faces, 6

; The camera viewport is assumed to be [-1,+1] across its widest axis.
; Therefore we multiply all projected coordinates by the screen width/2
; in order to map the viewport onto the entire screen.

.equ VIEWPORT_SCALE,    (Screen_Width /2) * PRECISION_MULTIPLIER
.equ VIEWPORT_CENTRE_X, (Screen_Width /2) * PRECISION_MULTIPLIER
.equ VIEWPORT_CENTRE_Y, 144 * PRECISION_MULTIPLIER

; ============================================================================
; Scene data.
; ============================================================================

; For simplicity, we assume that the camera has a FOV of 90 degrees, so the
; distance to the view plane is 'd' is the same as the viewport scale. All
; coordinates (x,y) lying on the view plane +d from the camera map 1:1 with
; screen coordinates.
;
;   h = viewport_scale / d.
;
; However as much of our maths in the scene is calculated as [8.16] maximum
; precision, having a camera distance of 160 only leaves 96 untis of depth
; to place objects within z=[0, 96] before potential problems occur.
;
; To solve this we use a smaller camera distance. d=80, giving h=160/80=2.
; This means that all vertex coordinates will be multiplied up by 2 when
; transformed to screen coordinates. E.g. the point (32,32,0) will map
; to (64,64) on the screen.
;
; This now gives us z=[0,176] to play with before any overflow errors are
; likely to occur. If this does happen, then we can further reduce the
; coordinate space and use d=40, h=4, etc.


camera_pos:
    VECTOR3 0.0, 0.0, -80.0

; Note camera is fixed to view down +z axis.
; TODO: Camera rotation/direction/look at?

object_pos:
    VECTOR3 0.0, 0.0, 32.0

object_pos_camera_relative:
    VECTOR3 0.0, 0.0, 0.0

object_rot:
    VECTOR3 0.0, 0.0, 0.0

object_scale:
    FLOAT_TO_FP 1.0
    
object_transform:
    MATRIX33_IDENTITY

normal_transform:           ; Rotation only.
    MATRIX33_IDENTITY

temp_matrix_1:
    MATRIX33_IDENTITY

temp_matrix_2:
    MATRIX33_IDENTITY

temp_vector_1:
    VECTOR3_ZERO

temp_vector_2:
    VECTOR3_ZERO

; ============================================================================
; ============================================================================

init_3d_scene:
    str lr, [sp, #-4]!

    adr r2, object_transform
    bl matrix_make_identity

    ldr pc, [sp], #4

; ============================================================================
; ============================================================================

update_3d_scene:
    str lr, [sp, #-4]!

    ; TODO: Optimise creation of rotation matrix.
    ;       Can compute this directly w/out multiplying matrices.

    .if 1
    ; Create rotation matrix as object transform.
    adr r2, temp_matrix_1
    ldr r0, object_rot + 0
    bl matrix_make_rotate_x     ; T1=rot_x

    adr r2, object_transform
    ldr r0, object_rot + 4
    bl matrix_make_rotate_y     ; OT=rot_y

    adr r0, temp_matrix_1
    adr r1, object_transform
    adr r2, temp_matrix_2
    bl matrix_multiply          ; T2=T1.OT

    adr r2, temp_matrix_1
    ldr r0, object_rot + 8
    bl matrix_make_rotate_z     ; T1=rot_z

    adr r0, temp_matrix_2
    adr r1, temp_matrix_1
    adr r2, normal_transform    ; NT=T2.T1  <== rotation only.
    bl matrix_multiply

    ldr r0, object_scale
    adr r2, temp_matrix_2
    bl matrix_make_scale        ; T2=scale

    adr r0, temp_matrix_2
    adr r1, normal_transform
    adr r2, object_transform    ; OT=T2.NT
    bl matrix_multiply
    .else
    ; Updating the rotation matrix in this way resulting in minification.
    ; Presume repeated precision loss during mutiply causing this.
    ; Would need the rotation only matrix multiplication routine here.
    adr r0, object_transform
    adr r1, delta_transform
    adr r2, temp_matrix
    bl matrix_multiply

    adr r0, object_transform
    adr r2, temp_matrix
    ldmia r2!, {r3-r11}
    stmia r0!, {r3-r11}
    .endif

    ; Subtract camera position from object position.
    adr r12, camera_pos
    ldmia r12, {r3-r5}

    adr r11, object_pos
    ldmia r11, {r6-r8}

    sub r6, r6, r3
    sub r7, r7, r4
    sub r8, r8, r5

    ; Camera relative object position.
    adr r11, object_pos_camera_relative
    stmia r11, {r6-r8}

    ; Transform vertices in scene.
    adr r0, object_transform
    adr r1, object_verts
    adr r2, transformed_verts
    mov r10, #object_num_verts
    .1:
    ; R0=ptr to matrix, R1=vector A, R2=vector B
    bl matrix_multiply_vector
    ; TODO: Array version of this function.

    ldmia r2, {r3-r5}
    ; Add camera relative object position to transform vertex.
    ldmia r11, {r6-r8}
    add r3, r3, r6
    add r4, r4, r7
    add r5, r5, r8
    stmia r2!, {r3-r5}
    
    add r1, r1, #VECTOR3_SIZE
    subs r10, r10, #1
    bne .1

    ; Transform normals.
    adr r0, normal_transform
    adr r1, object_face_normals
    adr r2, transformed_normals
    mov r10, #object_num_faces
    .2:
    ; R0=ptr to matrix, R1=vector A, R2=vector B
    bl matrix_multiply_vector
    ; TODO: Array version of this function.
    add r1, r1, #VECTOR3_SIZE
    add r2, r2, #VECTOR3_SIZE
    subs r10, r10, #1
    bne .2

    ; Update any scene vars, camera, object position etc. (Rocket?)
    .if 0
    mov r1, #MATHS_CONST_HALF    ; ROTATION_X
    ldr r0, object_rot+0
    add r0, r0, r1
    bic r0, r0, #0xff000000         ; brads
    str r0, object_rot+0

    mov r1, #MATHS_CONST_HALF    ; ROTATION_Y
    ldr r0, object_rot+4
    add r0, r0, r1
    bic r0, r0, #0xff000000         ; brads
    str r0, object_rot+4

    mov r1, #MATHS_CONST_HALF    ; ROTATION_Z
    ldr r0, object_rot+8
    add r0, r0, r1
    bic r0, r0, #0xff000000         ; brads
    str r0, object_rot+8
    .else
	mov r0, #0
	swi QTM_ReadVULevels
	; R0 = word containing 1 byte per channel 1-4 VU bar heights 0-64
    ; TODO: Finalise mapping of vu levels to scale & rotation deltas.
    and r10, r0, #0xff              ; channel 1 = scale
    mov r1, #MATHS_CONST_1
    add r1, r1, r10, asl #9         ; scale maps [1, 1.5]
    str r1, object_scale

    ; TODO: Make this code more compact.
  	mov r10, r0, lsr #8             ; channel 2 = inc_x
	and r10, r10, #0xff
    mov r10, r10, asl #11           ; inc_x maps [0, 2]
    ldr r1, object_rot + 0
    add r1, r1, r10                 ; object_rot_x += inc_x
    str r1, object_rot + 0

  	mov r10, r0, lsr #16            ; channel 3 = inc_y
	and r10, r10, #0xff
    mov r10, r10, asl #11           ; inc_y maps [0, 2]
    ldr r1, object_rot + 4
    add r1, r1, r10                 ; object_rot_y += inc_y
    str r1, object_rot + 4

  	mov r10, r0, lsr #24            ; channel 4 = inc_z
	and r10, r10, #0xff
    mov r10, r10, asl #11           ; inc_z maps [0, 2]
    ldr r1, object_rot + 8
    add r1, r1, r10                 ; object_rot_z += inc_z
    str r1, object_rot + 8
    .endif

    ldr pc, [sp], #4

; ============================================================================
; ============================================================================

; R12=screen addr
draw_3d_scene:
    str lr, [sp, #-4]!

    ; Stash screen addr for now.
    str r12, [sp, #-4]!

    ; Project vertices to screen.
    adr r2, transformed_verts
    mov r11, #object_num_verts
    adr r12, projected_verts
    .1:
    ; R2=ptr to world pos vector
    bl project_to_screen
    ; R0=screen_x, R1=screen_y [16.16]
    mov r0, r0, asr #16         ; [16.0]
    mov r1, r1, asr #16         ; [16.0]
    stmia r12!, {r0, r1}
    add r2, r2, #VECTOR3_SIZE
    subs r11, r11, #1
    bne .1

    ldr r12, [sp], #4           ; pop screen addr

    ; Plot faces as polys.
    adr r11, object_face_indices
    adr r10, projected_verts
    mov r9, #0                  ; face count
    .2:
    ldrb r5, [r11, #0]          ; vertex0 of polygon.
    
    adr r1, transformed_verts
    add r1, r1, r5, lsl #3
    add r1, r1, r5, lsl #2      ; transformed_verts + index*12
    adr r2, transformed_normals
    add r2, r2, r9, lsl #3      ; face_normal
    add r2, r2, r9, lsl #2      ; face_normal

    ; TODO: Inline?
    bl backface_cull_test       ; (vertex0 - camera_pos).face_normal

    cmp r0, #0                  
    bpl .3                      ; normal facing away from the view direction.

    mov r2, r10                 ; projected vertex array.
    ldr r3, [r11]               ; quad indices.
    stmfd sp!, {r9-r12}
    add r4, r9, #6              ; colour index.
    bl polygon_plot_quad
    ldmfd sp!, {r9-r12}

    .3:
    add r11, r11, #4
    add r9, r9, #1
    cmp r9, #object_num_faces
    bne .2

    ldr pc, [sp], #4

; Backfacing culling test.
; Parameters:
;  R1=ptr to transformed vertex in camera relative space
;  R2=ptr to face normal vector
; Return:
;  R0=dot product of (v0-cp).n
; Trashes: r3-r8
backface_cull_test:
    str lr, [sp, #-4]!

    ldmia r1, {r3-r5}
    ; vector A already in (r3, r4, r5)
    ; vector B = face normal
    bl vector_dot_product_load_B
    ldr pc, [sp], #4


; Project world position to screen coordinates.
;
; R2=ptr to camera relative transformed position
; Returns:
;  R0=screen x
;  R1=screen y
; Trashes: R3-R10
project_to_screen:
    str lr, [sp, #-4]!

    ; Vertex already transformed and camera relative.
    ldmia r2, {r3-r5}           ; (x,y,z)

    ; vp_centre_x + vp_scale * (x-cx) / (z-cz)
    mov r0, r3                  ; (x-cx)
    mov r1, r5                  ; (z-cz)
    bl divide                   ; (x-cx)/(z-cz)
                                ; [0.16]
    mov r7, #VIEWPORT_SCALE>>12 ; [16.4]
    mul r6, r0, r7              ; [12.20]
    mov r6, r6, asr #4          ; [12.16]
    mov r8, #VIEWPORT_CENTRE_X  ; [16.16]
    add r6, r6, r8

    ; Flip Y axis as we want +ve Y to point up the screen!
    ; vp_centre_y - vp_scale * (y-cy) / (z-cz)
    mov r0, r4                  ; (y-cy)
    mov r1, r5                  ; (z-cz)
    bl divide                   ; (y-cy)/(z-cz)
                                ; [0.16]
    mov r7, #VIEWPORT_SCALE>>12 ; [16.4]
    mul r1, r0, r7              ; [12.20]
    mov r1, r1, asr #4          ; [12.16]
    mov r8, #VIEWPORT_CENTRE_Y  ; [16.16]
    sub r1, r8, r1              ; [16.16]

    mov r0, r6
    ldr pc, [sp], #4


; ============================================================================
; Object data: CUBE
;
;         4         5        y
;          +------+          ^  z
;         /      /|          |/
;        /      / |          +--> x
;     0 +------+ 1|
;       | 7 +  |  + 6
;       |      | /
;       |      |/
;       +------+
;      3        2
; ============================================================================

object_verts:
    VECTOR3 -16.0,  16.0, -16.0
    VECTOR3  16.0,  16.0, -16.0
    VECTOR3  16.0, -16.0, -16.0
    VECTOR3 -16.0, -16.0, -16.0
    VECTOR3 -16.0,  16.0,  16.0
    VECTOR3  16.0,  16.0,  16.0
    VECTOR3  16.0, -16.0,  16.0
    VECTOR3 -16.0, -16.0,  16.0

; Winding order is clockwise (from outside)
object_face_indices:
    .byte 0, 1, 2, 3
    .byte 1, 5, 6, 2
    .byte 5, 4, 7, 6
    .byte 4, 0, 3, 7
    .byte 0, 4, 5, 1
    .byte 2, 3, 7, 6

object_face_normals:
    VECTOR3  0.0,  0.0, -1.0
    VECTOR3  1.0,  0.0,  0.0
    VECTOR3  0.0,  0.0,  1.0
    VECTOR3 -1.0,  0.0,  0.0
    VECTOR3  0.0,  1.0,  0.0
    VECTOR3  0.0  -1.0,  0.0
 
 ;TODO: Object face colours or vertex colours etc.

; ============================================================================
; Scene data.
; ============================================================================

transformed_verts:
    .skip OBJ_MAX_VERTS * VECTOR3_SIZE

transformed_normals:
    .skip OBJ_MAX_FACES * VECTOR3_SIZE

; TODO: Decide on how to store these, maybe packed or separate array?
projected_verts:
    .skip OBJ_MAX_VERTS * 2 * 4

polygon_buffer:
    .skip OBJ_VERTS_PER_FACE * 2 * 4

; ============================================================================
