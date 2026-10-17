# Camara libre v3 - The 3rd Birthday (ES ULES01513). Cueva 0x08800200; datos 0x08800100:
#  +0x100 activo | +0x104/108/10C direccion unitaria ojo-objetivo | +0x110 elevacion de la mirada (sube el objetivo)
#  +0x120 ojo calculado (vec4) | +0x130 dx,dy,dz originales del juego | +0x140 objetivo elevado (vec4)
        .set noreorder
        .set noat
cave:
        lui     $t0, 0x0880
        lwc1    $f0, 0($a1)
        lwc1    $f1, 4($a1)
        lwc1    $f2, 8($a1)
        lwc1    $f3, 0($a2)
        lwc1    $f4, 4($a2)
        lwc1    $f5, 8($a2)
        sub.s   $f0, $f0, $f3
        sub.s   $f1, $f1, $f4
        sub.s   $f2, $f2, $f5
        swc1    $f0, 0x130($t0)
        swc1    $f1, 0x134($t0)
        swc1    $f2, 0x138($t0)
        lw      $t1, 0x100($t0)
        beq     $t1, $zero, orig
        nop
        mul.s   $f6, $f0, $f0
        mul.s   $f7, $f1, $f1
        add.s   $f6, $f6, $f7
        mul.s   $f7, $f2, $f2
        add.s   $f6, $f6, $f7
        sqrt.s  $f6, $f6
        lwc1    $f7, 0x104($t0)
        mul.s   $f7, $f7, $f6
        add.s   $f7, $f7, $f3
        swc1    $f7, 0x120($t0)
        lwc1    $f8, 0x108($t0)
        mul.s   $f8, $f8, $f6
        add.s   $f8, $f8, $f4
        swc1    $f8, 0x124($t0)
        lwc1    $f9, 0x10C($t0)
        mul.s   $f9, $f9, $f6
        add.s   $f9, $f9, $f5
        swc1    $f9, 0x128($t0)
        lw      $t1, 12($a1)
        sw      $t1, 0x12C($t0)
        addiu   $a1, $t0, 0x120
        lwc1    $f10, 0x110($t0)       # elevacion
        add.s   $f4, $f4, $f10
        swc1    $f3, 0x140($t0)
        swc1    $f4, 0x144($t0)
        swc1    $f5, 0x148($t0)
        lw      $t1, 12($a2)
        sw      $t1, 0x14C($t0)
        addiu   $a2, $t0, 0x140
orig:
        j       0x08B209CC
        nop
