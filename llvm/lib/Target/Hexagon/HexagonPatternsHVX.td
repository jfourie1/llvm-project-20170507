def SDTVecLeaf:
  SDTypeProfile<1, 0, [SDTCisVec<0>]>;
def SDTVecBinOp:
  SDTypeProfile<1, 2, [SDTCisVec<0>, SDTCisVec<1>, SDTCisSameAs<1,2>]>;

def SDTHexagonVEXTRACTW: SDTypeProfile<1, 2,
  [SDTCisVT<0, i32>, SDTCisVec<1>, SDTCisVT<2, i32>]>;
def HexagonVEXTRACTW : SDNode<"HexagonISD::VEXTRACTW", SDTHexagonVEXTRACTW>;

def SDTHexagonVINSERTW0: SDTypeProfile<1, 2,
  [SDTCisVec<0>, SDTCisSameAs<0, 1>, SDTCisVT<2, i32>]>;
def HexagonVINSERTW0: SDNode<"HexagonISD::VINSERTW0", SDTHexagonVINSERTW0>;

def SDTHexagonVSPLATW: SDTypeProfile<1, 1, [SDTCisVec<0>, SDTCisVT<1, i32>]>;
def HexagonVSPLATW: SDNode<"HexagonISD::VSPLATW", SDTHexagonVSPLATW>;

def HwLen2: SDNodeXForm<imm, [{
  const auto &ST = static_cast<const HexagonSubtarget&>(CurDAG->getSubtarget());
  return CurDAG->getTargetConstant(ST.getVectorLength()/2, SDLoc(N), MVT::i32);
}]>;

def Q2V: OutPatFrag<(ops node:$Qs), (V6_vandqrt $Qs, (A2_tfrsi -1))>;

def Combinev: OutPatFrag<(ops node:$Vs, node:$Vt),
  (REG_SEQUENCE HvxWR, $Vs, vsub_hi, $Vt, vsub_lo)>;

def Combineq: OutPatFrag<(ops node:$Qs, node:$Qt),
  (V6_vandvrt
    (V6_vor
      (V6_vror (V6_vpackeb (V6_vd0), (Q2V $Qs)),
               (A2_tfrsi (HwLen2 (i32 0)))),  // Half the vector length
      (V6_vpackeb (V6_vd0), (Q2V $Qt))),
    (A2_tfrsi -1))>;

def LoVec: OutPatFrag<(ops node:$Vs), (EXTRACT_SUBREG $Vs, vsub_lo)>;
def HiVec: OutPatFrag<(ops node:$Vs), (EXTRACT_SUBREG $Vs, vsub_hi)>;

def HexagonVZERO:      SDNode<"HexagonISD::VZERO",      SDTVecLeaf>;
def HexagonQCAT:       SDNode<"HexagonISD::QCAT",       SDTVecBinOp>;
def HexagonQTRUE:      SDNode<"HexagonISD::QTRUE",      SDTVecLeaf>;
def HexagonQFALSE:     SDNode<"HexagonISD::QFALSE",     SDTVecLeaf>;

def vzero:  PatFrag<(ops), (HexagonVZERO)>;
def qtrue:  PatFrag<(ops), (HexagonQTRUE)>;
def qfalse: PatFrag<(ops), (HexagonQFALSE)>;
def qcat:   PatFrag<(ops node:$Qs, node:$Qt),
                    (HexagonQCAT node:$Qs, node:$Qt)>;

def qnot: PatFrag<(ops node:$Qs), (xor node:$Qs, qtrue)>;

def VSxtb: OutPatFrag<(ops node:$Vs), (V6_vunpackb  $Vs)>;
def VSxth: OutPatFrag<(ops node:$Vs), (V6_vunpackh  $Vs)>;
def VZxtb: OutPatFrag<(ops node:$Vs), (V6_vunpackub $Vs)>;
def VZxth: OutPatFrag<(ops node:$Vs), (V6_vunpackuh $Vs)>;

def SplatB: SDNodeXForm<imm, [{
  uint32_t V = N->getZExtValue();
  assert(isUInt<8>(V));
  uint32_t S = V << 24 | V << 16 | V << 8 | V;
  return CurDAG->getTargetConstant(S, SDLoc(N), MVT::i32);
}]>;

def SplatH: SDNodeXForm<imm, [{
  uint32_t V = N->getZExtValue();
  assert(isUInt<16>(V));
  return CurDAG->getTargetConstant(V << 16 | V, SDLoc(N), MVT::i32);
}]>;

def IsVecOff : PatLeaf<(i32 imm), [{
  int32_t V = N->getSExtValue();
  int32_t VecSize = HRI->getSpillSize(Hexagon::HvxVRRegClass);
  assert(isPowerOf2_32(VecSize));
  if ((uint32_t(V) & (uint32_t(VecSize)-1)) != 0)
    return false;
  int32_t L = Log2_32(VecSize);
  return isInt<4>(V >> L);
}]>;


def alignedload: PatFrag<(ops node:$a), (load $a), [{
  return isAlignedMemNode(dyn_cast<MemSDNode>(N));
}]>;

def unalignedload: PatFrag<(ops node:$a), (load $a), [{
  return !isAlignedMemNode(dyn_cast<MemSDNode>(N));
}]>;

def alignedstore: PatFrag<(ops node:$v, node:$a), (store $v, $a), [{
  return isAlignedMemNode(dyn_cast<MemSDNode>(N));
}]>;

def unalignedstore: PatFrag<(ops node:$v, node:$a), (store $v, $a), [{
  return !isAlignedMemNode(dyn_cast<MemSDNode>(N));
}]>;


// HVX loads

multiclass HvxLd_pat<InstHexagon MI, PatFrag Load, ValueType ResType,
                     PatFrag ImmPred> {
  def: Pat<(ResType (Load I32:$Rt)),
           (MI I32:$Rt, 0)>;
  def: Pat<(ResType (Load (add I32:$Rt, ImmPred:$s))),
           (MI I32:$Rt, imm:$s)>;
  // The HVX selection code for shuffles can generate vector constants.
  // Calling "Select" on the resulting loads from CP fails without these
  // patterns.
  def: Pat<(ResType (Load (HexagonCP tconstpool:$A))),
           (MI (A2_tfrsi imm:$A), 0)>;
  def: Pat<(ResType (Load (HexagonAtPcrel tconstpool:$A))),
           (MI (C4_addipc imm:$A), 0)>;
}

multiclass HvxLda_pat<InstHexagon MI, PatFrag Load, ValueType ResType,
                      PatFrag ImmPred> {
  let AddedComplexity = 50 in {
    def: Pat<(ResType (Load (valignaddr I32:$Rt))),
             (MI I32:$Rt, 0)>;
    def: Pat<(ResType (Load (add (valignaddr I32:$Rt), ImmPred:$Off))),
             (MI I32:$Rt, imm:$Off)>;
  }
  defm: HvxLd_pat<MI, Load, ResType, ImmPred>;
}

let Predicates = [UseHVX] in {
  defm: HvxLda_pat<V6_vL32b_nt_ai, alignednontemporalload, VecI8,  IsVecOff>;
  defm: HvxLda_pat<V6_vL32b_nt_ai, alignednontemporalload, VecI16, IsVecOff>;
  defm: HvxLda_pat<V6_vL32b_nt_ai, alignednontemporalload, VecI32, IsVecOff>;

  defm: HvxLda_pat<V6_vL32b_ai, alignedload, VecI8,  IsVecOff>;
  defm: HvxLda_pat<V6_vL32b_ai, alignedload, VecI16, IsVecOff>;
  defm: HvxLda_pat<V6_vL32b_ai, alignedload, VecI32, IsVecOff>;

  defm: HvxLd_pat<V6_vL32Ub_ai,  unalignedload, VecI8,  IsVecOff>;
  defm: HvxLd_pat<V6_vL32Ub_ai,  unalignedload, VecI16, IsVecOff>;
  defm: HvxLd_pat<V6_vL32Ub_ai,  unalignedload, VecI32, IsVecOff>;
}

// HVX stores

multiclass HvxSt_pat<InstHexagon MI, PatFrag Store, PatFrag ImmPred,
                     PatFrag Value> {
  def: Pat<(Store Value:$Vs, I32:$Rt),
           (MI I32:$Rt, 0, Value:$Vs)>;
  def: Pat<(Store Value:$Vs, (add I32:$Rt, ImmPred:$s)),
           (MI I32:$Rt, imm:$s, Value:$Vs)>;
}

let Predicates = [UseHVX] in {
  defm: HvxSt_pat<V6_vS32b_nt_ai, alignednontemporalstore, IsVecOff, HVI8>;
  defm: HvxSt_pat<V6_vS32b_nt_ai, alignednontemporalstore, IsVecOff, HVI16>;
  defm: HvxSt_pat<V6_vS32b_nt_ai, alignednontemporalstore, IsVecOff, HVI32>;

  defm: HvxSt_pat<V6_vS32b_ai, alignedstore, IsVecOff, HVI8>;
  defm: HvxSt_pat<V6_vS32b_ai, alignedstore, IsVecOff, HVI16>;
  defm: HvxSt_pat<V6_vS32b_ai, alignedstore, IsVecOff, HVI32>;

  defm: HvxSt_pat<V6_vS32Ub_ai, unalignedstore, IsVecOff, HVI8>;
  defm: HvxSt_pat<V6_vS32Ub_ai, unalignedstore, IsVecOff, HVI16>;
  defm: HvxSt_pat<V6_vS32Ub_ai, unalignedstore, IsVecOff, HVI32>;
}

// Bitcasts between same-size vector types are no-ops, except for the
// actual type change.
class Bitcast<ValueType ResTy, ValueType InpTy, RegisterClass RC>
  : Pat<(ResTy (bitconvert (InpTy RC:$Val))), (ResTy RC:$Val)>;

let Predicates = [UseHVX] in {
  def: Bitcast<VecI8,   VecI16,  HvxVR>;
  def: Bitcast<VecI8,   VecI32,  HvxVR>;
  def: Bitcast<VecI16,  VecI8,   HvxVR>;
  def: Bitcast<VecI16,  VecI32,  HvxVR>;
  def: Bitcast<VecI32,  VecI8,   HvxVR>;
  def: Bitcast<VecI32,  VecI16,  HvxVR>;

  def: Bitcast<VecPI8,  VecPI16, HvxWR>;
  def: Bitcast<VecPI8,  VecPI32, HvxWR>;
  def: Bitcast<VecPI16, VecPI8,  HvxWR>;
  def: Bitcast<VecPI16, VecPI32, HvxWR>;
  def: Bitcast<VecPI32, VecPI8,  HvxWR>;
  def: Bitcast<VecPI32, VecPI16, HvxWR>;
}

let Predicates = [UseHVX] in {
  def: Pat<(VecI8   vzero), (V6_vd0)>;
  def: Pat<(VecI16  vzero), (V6_vd0)>;
  def: Pat<(VecI32  vzero), (V6_vd0)>;
  // Use V6_vsubw_dv instead.
  def: Pat<(VecPI8  vzero), (Combinev (V6_vd0), (V6_vd0))>;
  def: Pat<(VecPI16 vzero), (Combinev (V6_vd0), (V6_vd0))>;
  def: Pat<(VecPI32 vzero), (Combinev (V6_vd0), (V6_vd0))>;

  def: Pat<(VecPI8 (concat_vectors HVI8:$Vs, HVI8:$Vt)),
           (Combinev HvxVR:$Vt, HvxVR:$Vs)>;
  def: Pat<(VecPI16 (concat_vectors HVI16:$Vs, HVI16:$Vt)),
           (Combinev HvxVR:$Vt, HvxVR:$Vs)>;
  def: Pat<(VecPI32 (concat_vectors HVI32:$Vs, HVI32:$Vt)),
           (Combinev HvxVR:$Vt, HvxVR:$Vs)>;

  def: Pat<(VecQ8  (qcat HQ16:$Qs, HQ16:$Qt)), (Combineq $Qt, $Qs)>;
  def: Pat<(VecQ16 (qcat HQ32:$Qs, HQ32:$Qt)), (Combineq $Qt, $Qs)>;

  def: Pat<(HexagonVEXTRACTW HVI8:$Vu, I32:$Rs),
           (V6_extractw HvxVR:$Vu, I32:$Rs)>;
  def: Pat<(HexagonVEXTRACTW HVI16:$Vu, I32:$Rs),
           (V6_extractw HvxVR:$Vu, I32:$Rs)>;
  def: Pat<(HexagonVEXTRACTW HVI32:$Vu, I32:$Rs),
           (V6_extractw HvxVR:$Vu, I32:$Rs)>;

  def: Pat<(HexagonVINSERTW0 HVI8:$Vu,  I32:$Rt),
           (V6_vinsertwr HvxVR:$Vu, I32:$Rt)>;
  def: Pat<(HexagonVINSERTW0 HVI16:$Vu, I32:$Rt),
           (V6_vinsertwr HvxVR:$Vu, I32:$Rt)>;
  def: Pat<(HexagonVINSERTW0 HVI32:$Vu, I32:$Rt),
           (V6_vinsertwr HvxVR:$Vu, I32:$Rt)>;
}

def Vsplatib: OutPatFrag<(ops node:$V),  (V6_lvsplatw (ToI32 (SplatB $V)))>;
def Vsplatih: OutPatFrag<(ops node:$V),  (V6_lvsplatw (ToI32 (SplatH $V)))>;
def Vsplatiw: OutPatFrag<(ops node:$V),  (V6_lvsplatw (ToI32 $V))>;

def Vsplatrb: OutPatFrag<(ops node:$Rs), (V6_lvsplatw (S2_vsplatrb $Rs))>;
def Vsplatrh: OutPatFrag<(ops node:$Rs),
                         (V6_lvsplatw (A2_combine_ll $Rs, $Rs))>;
def Vsplatrw: OutPatFrag<(ops node:$Rs), (V6_lvsplatw $Rs)>;

def Rep: OutPatFrag<(ops node:$N), (Combinev $N, $N)>;

let Predicates = [UseHVX] in {
  let AddedComplexity = 10 in {
    def: Pat<(VecI8   (HexagonVSPLAT u8_0ImmPred:$V)),  (Vsplatib $V)>;
    def: Pat<(VecI16  (HexagonVSPLAT u16_0ImmPred:$V)), (Vsplatih $V)>;
    def: Pat<(VecI32  (HexagonVSPLAT anyimm:$V)),       (Vsplatiw $V)>;
    def: Pat<(VecPI8  (HexagonVSPLAT u8_0ImmPred:$V)),  (Rep (Vsplatib $V))>;
    def: Pat<(VecPI16 (HexagonVSPLAT u16_0ImmPred:$V)), (Rep (Vsplatih $V))>;
    def: Pat<(VecPI32 (HexagonVSPLAT anyimm:$V)),       (Rep (Vsplatiw $V))>;
  }
  def: Pat<(VecI8   (HexagonVSPLAT I32:$Rs)), (Vsplatrb $Rs)>;
  def: Pat<(VecI16  (HexagonVSPLAT I32:$Rs)), (Vsplatrh $Rs)>;
  def: Pat<(VecI32  (HexagonVSPLAT I32:$Rs)), (Vsplatrw $Rs)>;
  def: Pat<(VecPI8  (HexagonVSPLAT I32:$Rs)), (Rep (Vsplatrb $Rs))>;
  def: Pat<(VecPI16 (HexagonVSPLAT I32:$Rs)), (Rep (Vsplatrh $Rs))>;
  def: Pat<(VecPI32 (HexagonVSPLAT I32:$Rs)), (Rep (Vsplatrw $Rs))>;

  def: Pat<(VecI8   (HexagonVSPLATW I32:$Rs)), (V6_lvsplatw I32:$Rs)>;
  def: Pat<(VecI16  (HexagonVSPLATW I32:$Rs)), (V6_lvsplatw I32:$Rs)>;
  def: Pat<(VecI32  (HexagonVSPLATW I32:$Rs)), (V6_lvsplatw I32:$Rs)>;
  def: Pat<(VecPI8  (HexagonVSPLATW I32:$Rs)), (Rep (V6_lvsplatw I32:$Rs))>;
  def: Pat<(VecPI16 (HexagonVSPLATW I32:$Rs)), (Rep (V6_lvsplatw I32:$Rs))>;
  def: Pat<(VecPI32 (HexagonVSPLATW I32:$Rs)), (Rep (V6_lvsplatw I32:$Rs))>;
}

let Predicates = [UseHVX] in {
  def: Pat<(add HVI8:$Vs,  HVI8:$Vt),   (V6_vaddb    HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(add HVI16:$Vs, HVI16:$Vt),  (V6_vaddh    HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(add HVI32:$Vs, HVI32:$Vt),  (V6_vaddw    HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(add HWI8:$Vs,  HWI8:$Vt),   (V6_vaddb_dv HvxWR:$Vs, HvxWR:$Vt)>;
  def: Pat<(add HWI16:$Vs, HWI16:$Vt),  (V6_vaddh_dv HvxWR:$Vs, HvxWR:$Vt)>;
  def: Pat<(add HWI32:$Vs, HWI32:$Vt),  (V6_vaddw_dv HvxWR:$Vs, HvxWR:$Vt)>;

  def: Pat<(sub HVI8:$Vs,  HVI8:$Vt),   (V6_vsubb    HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(sub HVI16:$Vs, HVI16:$Vt),  (V6_vsubh    HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(sub HVI32:$Vs, HVI32:$Vt),  (V6_vsubw    HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(sub HWI8:$Vs,  HWI8:$Vt),   (V6_vsubb_dv HvxWR:$Vs, HvxWR:$Vt)>;
  def: Pat<(sub HWI16:$Vs, HWI16:$Vt),  (V6_vsubh_dv HvxWR:$Vs, HvxWR:$Vt)>;
  def: Pat<(sub HWI32:$Vs, HWI32:$Vt),  (V6_vsubw_dv HvxWR:$Vs, HvxWR:$Vt)>;

  def: Pat<(and HVI8:$Vs,  HVI8:$Vt),   (V6_vand  HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(and HVI16:$Vs, HVI16:$Vt),  (V6_vand  HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(and HVI32:$Vs, HVI32:$Vt),  (V6_vand  HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(or  HVI8:$Vs,  HVI8:$Vt),   (V6_vor   HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(or  HVI16:$Vs, HVI16:$Vt),  (V6_vor   HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(or  HVI32:$Vs, HVI32:$Vt),  (V6_vor   HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(xor HVI8:$Vs,  HVI8:$Vt),   (V6_vxor  HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(xor HVI16:$Vs, HVI16:$Vt),  (V6_vxor  HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(xor HVI32:$Vs, HVI32:$Vt),  (V6_vxor  HvxVR:$Vs, HvxVR:$Vt)>;

  def: Pat<(vselect HQ8:$Qu, HVI8:$Vs, HVI8:$Vt),
           (V6_vmux HvxQR:$Qu, HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(vselect HQ16:$Qu, HVI16:$Vs, HVI16:$Vt),
           (V6_vmux HvxQR:$Qu, HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(vselect HQ32:$Qu, HVI32:$Vs, HVI32:$Vt),
           (V6_vmux HvxQR:$Qu, HvxVR:$Vs, HvxVR:$Vt)>;

  def: Pat<(vselect (qnot HQ8:$Qu), HVI8:$Vs, HVI8:$Vt),
           (V6_vmux HvxQR:$Qu, HvxVR:$Vt, HvxVR:$Vs)>;
  def: Pat<(vselect (qnot HQ16:$Qu), HVI16:$Vs, HVI16:$Vt),
           (V6_vmux HvxQR:$Qu, HvxVR:$Vt, HvxVR:$Vs)>;
  def: Pat<(vselect (qnot HQ32:$Qu), HVI32:$Vs, HVI32:$Vt),
           (V6_vmux HvxQR:$Qu, HvxVR:$Vt, HvxVR:$Vs)>;

  def: Pat<(VecPI16 (sext HVI8:$Vs)),  (VSxtb $Vs)>;
  def: Pat<(VecPI32 (sext HVI16:$Vs)), (VSxth $Vs)>;
  def: Pat<(VecPI16 (zext HVI8:$Vs)),  (VZxtb $Vs)>;
  def: Pat<(VecPI32 (zext HVI16:$Vs)), (VZxth $Vs)>;

  def: Pat<(VecI16 (sext_invec HVI8:$Vs)),  (LoVec (VSxtb $Vs))>;
  def: Pat<(VecI32 (sext_invec HVI16:$Vs)), (LoVec (VSxth $Vs))>;
  def: Pat<(VecI32 (sext_invec HVI8:$Vs)),
           (LoVec (VSxth (LoVec (VSxtb $Vs))))>;
  def: Pat<(VecPI16 (sext_invec HWI8:$Vss)),  (VSxtb (LoVec $Vss))>;
  def: Pat<(VecPI32 (sext_invec HWI16:$Vss)), (VSxth (LoVec $Vss))>;
  def: Pat<(VecPI32 (sext_invec HWI8:$Vss)),
           (VSxth (LoVec (VSxtb (LoVec $Vss))))>;

  def: Pat<(VecI16 (zext_invec HVI8:$Vs)),  (LoVec (VZxtb $Vs))>;
  def: Pat<(VecI32 (zext_invec HVI16:$Vs)), (LoVec (VZxth $Vs))>;
  def: Pat<(VecI32 (zext_invec HVI8:$Vs)),
           (LoVec (VZxth (LoVec (VZxtb $Vs))))>;
  def: Pat<(VecPI16 (zext_invec HWI8:$Vss)),  (VZxtb (LoVec $Vss))>;
  def: Pat<(VecPI32 (zext_invec HWI16:$Vss)), (VZxth (LoVec $Vss))>;
  def: Pat<(VecPI32 (zext_invec HWI8:$Vss)),
           (VZxth (LoVec (VZxtb (LoVec $Vss))))>;

  // The "source" types are not legal, and there are no parameterized
  // definitions for them, but they are length-specific.
  let Predicates = [UseHVX,UseHVX64B] in {
    def: Pat<(VecI16 (sext_inreg HVI16:$Vs, v32i8)),
             (V6_vasrh (V6_vaslh HVI16:$Vs, (A2_tfrsi 8)), (A2_tfrsi 8))>;
    def: Pat<(VecI32 (sext_inreg HVI32:$Vs, v16i8)),
             (V6_vasrw (V6_vaslw HVI32:$Vs, (A2_tfrsi 24)), (A2_tfrsi 24))>;
    def: Pat<(VecI32 (sext_inreg HVI32:$Vs, v16i16)),
             (V6_vasrw (V6_vaslw HVI32:$Vs, (A2_tfrsi 16)), (A2_tfrsi 16))>;
  }
  let Predicates = [UseHVX,UseHVX128B] in {
    def: Pat<(VecI16 (sext_inreg HVI16:$Vs, v64i8)),
             (V6_vasrh (V6_vaslh HVI16:$Vs, (A2_tfrsi 8)), (A2_tfrsi 8))>;
    def: Pat<(VecI32 (sext_inreg HVI32:$Vs, v32i8)),
             (V6_vasrw (V6_vaslw HVI32:$Vs, (A2_tfrsi 24)), (A2_tfrsi 24))>;
    def: Pat<(VecI32 (sext_inreg HVI32:$Vs, v32i16)),
             (V6_vasrw (V6_vaslw HVI32:$Vs, (A2_tfrsi 16)), (A2_tfrsi 16))>;
  }

  def: Pat<(HexagonVASL HVI8:$Vs, I32:$Rt),
           (V6_vpackeb (V6_vaslh (HiVec (VZxtb HvxVR:$Vs)), I32:$Rt),
                       (V6_vaslh (LoVec (VZxtb HvxVR:$Vs)), I32:$Rt))>;
  def: Pat<(HexagonVASR HVI8:$Vs, I32:$Rt),
           (V6_vpackeb (V6_vasrh (HiVec (VSxtb HvxVR:$Vs)), I32:$Rt),
                       (V6_vasrh (LoVec (VSxtb HvxVR:$Vs)), I32:$Rt))>;
  def: Pat<(HexagonVLSR HVI8:$Vs, I32:$Rt),
           (V6_vpackeb (V6_vlsrh (HiVec (VZxtb HvxVR:$Vs)), I32:$Rt),
                       (V6_vlsrh (LoVec (VZxtb HvxVR:$Vs)), I32:$Rt))>;

  def: Pat<(HexagonVASL HVI16:$Vs, I32:$Rt), (V6_vaslh HvxVR:$Vs, I32:$Rt)>;
  def: Pat<(HexagonVASL HVI32:$Vs, I32:$Rt), (V6_vaslw HvxVR:$Vs, I32:$Rt)>;
  def: Pat<(HexagonVASR HVI16:$Vs, I32:$Rt), (V6_vasrh HvxVR:$Vs, I32:$Rt)>;
  def: Pat<(HexagonVASR HVI32:$Vs, I32:$Rt), (V6_vasrw HvxVR:$Vs, I32:$Rt)>;
  def: Pat<(HexagonVLSR HVI16:$Vs, I32:$Rt), (V6_vlsrh HvxVR:$Vs, I32:$Rt)>;
  def: Pat<(HexagonVLSR HVI32:$Vs, I32:$Rt), (V6_vlsrw HvxVR:$Vs, I32:$Rt)>;

  def: Pat<(add HVI32:$Vx, (HexagonVASL HVI32:$Vu, I32:$Rt)),
           (V6_vaslw_acc HvxVR:$Vx, HvxVR:$Vu, I32:$Rt)>;
  def: Pat<(add HVI32:$Vx, (HexagonVASR HVI32:$Vu, I32:$Rt)),
           (V6_vasrw_acc HvxVR:$Vx, HvxVR:$Vu, I32:$Rt)>;

  def: Pat<(shl HVI16:$Vs, HVI16:$Vt), (V6_vaslhv HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(shl HVI32:$Vs, HVI32:$Vt), (V6_vaslwv HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(sra HVI16:$Vs, HVI16:$Vt), (V6_vasrhv HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(sra HVI32:$Vs, HVI32:$Vt), (V6_vasrwv HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(srl HVI16:$Vs, HVI16:$Vt), (V6_vlsrhv HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(srl HVI32:$Vs, HVI32:$Vt), (V6_vlsrwv HvxVR:$Vs, HvxVR:$Vt)>;

  def: Pat<(VecI8 (trunc HWI16:$Vss)),
           (V6_vpackeb (HiVec $Vss), (LoVec $Vss))>;
  def: Pat<(VecI16 (trunc HWI32:$Vss)),
           (V6_vpackeh (HiVec $Vss), (LoVec $Vss))>;

  def: Pat<(VecI16 (bswap HVI16:$Vs)),
           (V6_vdelta HvxVR:$Vs, (V6_lvsplatw (A2_tfrsi 0x01010101)))>;
  def: Pat<(VecI32 (bswap HVI32:$Vs)),
           (V6_vdelta HvxVR:$Vs, (V6_lvsplatw (A2_tfrsi 0x03030303)))>;
}

class HvxSel_pat<InstHexagon MI, PatFrag RegPred>
  : Pat<(select I1:$Pu, RegPred:$Vs, RegPred:$Vt),
        (MI I1:$Pu, RegPred:$Vs, RegPred:$Vt)>;

let Predicates = [HasV60T,UseHVX] in {
  def: HvxSel_pat<PS_vselect, HVI8>;
  def: HvxSel_pat<PS_vselect, HVI16>;
  def: HvxSel_pat<PS_vselect, HVI32>;
  def: HvxSel_pat<PS_wselect, HWI8>;
  def: HvxSel_pat<PS_wselect, HWI16>;
  def: HvxSel_pat<PS_wselect, HWI32>;
}

let Predicates = [UseHVX] in {
  def: Pat<(VecQ8   (qtrue)), (PS_qtrue)>;
  def: Pat<(VecQ16  (qtrue)), (PS_qtrue)>;
  def: Pat<(VecQ32  (qtrue)), (PS_qtrue)>;
  def: Pat<(VecQ8  (qfalse)), (PS_qfalse)>;
  def: Pat<(VecQ16 (qfalse)), (PS_qfalse)>;
  def: Pat<(VecQ32 (qfalse)), (PS_qfalse)>;

  def: Pat<(vnot  HQ8:$Qs), (V6_pred_not HvxQR:$Qs)>;
  def: Pat<(vnot HQ16:$Qs), (V6_pred_not HvxQR:$Qs)>;
  def: Pat<(vnot HQ32:$Qs), (V6_pred_not HvxQR:$Qs)>;
  def: Pat<(qnot  HQ8:$Qs), (V6_pred_not HvxQR:$Qs)>;
  def: Pat<(qnot HQ16:$Qs), (V6_pred_not HvxQR:$Qs)>;
  def: Pat<(qnot HQ32:$Qs), (V6_pred_not HvxQR:$Qs)>;

  def: Pat<(VecQ8  (and HQ8:$Qs,   HQ8:$Qt)),
           (V6_pred_and HvxQR:$Qs, HvxQR:$Qt)>;
  def: Pat<(VecQ16 (and HQ16:$Qs,  HQ16:$Qt)),
           (V6_pred_and HvxQR:$Qs, HvxQR:$Qt)>;
  def: Pat<(VecQ32 (and HQ32:$Qs,  HQ32:$Qt)),
           (V6_pred_and HvxQR:$Qs, HvxQR:$Qt)>;

  def: Pat<(VecQ8   (or HQ8:$Qs,   HQ8:$Qt)),
           (V6_pred_or  HvxQR:$Qs, HvxQR:$Qt)>;
  def: Pat<(VecQ16  (or HQ16:$Qs,  HQ16:$Qt)),
           (V6_pred_or  HvxQR:$Qs, HvxQR:$Qt)>;
  def: Pat<(VecQ32  (or HQ32:$Qs,  HQ32:$Qt)),
           (V6_pred_or  HvxQR:$Qs, HvxQR:$Qt)>;

  def: Pat<(VecQ8  (xor HQ8:$Qs,   HQ8:$Qt)),
           (V6_pred_xor HvxQR:$Qs, HvxQR:$Qt)>;
  def: Pat<(VecQ16 (xor HQ16:$Qs,  HQ16:$Qt)),
           (V6_pred_xor HvxQR:$Qs, HvxQR:$Qt)>;
  def: Pat<(VecQ32 (xor HQ32:$Qs,  HQ32:$Qt)),
           (V6_pred_xor HvxQR:$Qs, HvxQR:$Qt)>;

  def: Pat<(VecQ8 (seteq   HVI8:$Vs,  HVI8:$Vt)),
           (V6_veqb  HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(VecQ8 (setgt   HVI8:$Vs,  HVI8:$Vt)),
           (V6_vgtb  HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(VecQ8 (setugt  HVI8:$Vs,  HVI8:$Vt)),
           (V6_vgtub HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(VecQ16 (seteq  HVI16:$Vs, HVI16:$Vt)),
           (V6_veqh  HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(VecQ16 (setgt  HVI16:$Vs, HVI16:$Vt)),
           (V6_vgth  HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(VecQ16 (setugt HVI16:$Vs, HVI16:$Vt)),
           (V6_vgtuh HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(VecQ32 (seteq  HVI32:$Vs, HVI32:$Vt)),
           (V6_veqw  HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(VecQ32 (setgt  HVI32:$Vs, HVI32:$Vt)),
           (V6_vgtw  HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(VecQ32 (setugt HVI32:$Vs, HVI32:$Vt)),
           (V6_vgtuw HvxVR:$Vs, HvxVR:$Vt)>;
}
